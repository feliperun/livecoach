import AVFoundation
import CoreGraphics
import ScreenCaptureKit
import OSLog

/// Captura nativa dos dois lados:
///  - mic do usuário via `AVAudioEngine` (tag `.self`)
///  - áudio do sistema (interlocutor) via `ScreenCaptureKit` (tag `.other`)
///
/// Regra dos callbacks de áudio: fazer o mínimo. Aqui só empacotam o buffer e
/// entregam ao mundo async via `AsyncStream.Continuation`.
final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let log = Logger(subsystem: "CueMe", category: "AudioCapture")

    let chunks: AsyncStream<AudioChunk>
    private let continuation: AsyncStream<AudioChunk>.Continuation
    let events: AsyncStream<AudioCaptureEvent>
    private let eventsContinuation: AsyncStream<AudioCaptureEvent>.Continuation

    private let engine = AVAudioEngine()
    private var scStream: SCStream?
    private let scQueue = DispatchQueue(label: "CueMe.SCStreamOutput")
    private let stateLock = NSLock()
    private var systemDesired = false
    private var systemRecoveryTask: Task<Void, Never>?
    private var systemRecoveryAttempt = 0

    private let signalMonitor = AudioSignalMonitor()

    private var micRunning = false
    private var systemRunning = false
    private var captureOwnProcess = false   // modo treino: captar o TTS do próprio app

    /// Captura de sistema (interlocutor) ativa? Lido pela UI.
    var isSystemActive: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return systemRunning
    }

    override init() {
        var cont: AsyncStream<AudioChunk>.Continuation!
        self.chunks = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { cont = $0 }
        self.continuation = cont
        var eventCont: AsyncStream<AudioCaptureEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(32)) { eventCont = $0 }
        self.eventsContinuation = eventCont
        super.init()
    }

    // MARK: - Permissões

    static func requestMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    // MARK: - Ciclo de vida

    @MainActor
    func start(includeSystem: Bool, echoCancellation: Bool = false, captureOwnProcess: Bool = false) async throws {
        self.captureOwnProcess = captureOwnProcess
        eventsContinuation.yield(.state(.self, .waiting))
        try startMic(echoCancellation: echoCancellation)
        if includeSystem {
            setSystemDesired(true)
            eventsContinuation.yield(.state(.other, .recovering))
            do {
                try await startSystem()
            } catch {
                // Sistema é opcional: se a permissão de gravação de tela faltar,
                // seguimos só com o mic (mock interview de um lado).
                log.error("Falha ao iniciar captura de sistema: \(error.localizedDescription, privacy: .public)")
                eventsContinuation.yield(.state(.other, .unavailable))
            }
        } else {
            eventsContinuation.yield(.state(.other, .unavailable))
        }
    }

    @MainActor
    func stop() {
        if micRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            micRunning = false
        }
        setSystemDesired(false)
        systemRecoveryTask?.cancel()
        systemRecoveryTask = nil
        stateLock.lock()
        let stream = scStream
        scStream = nil
        systemRunning = false
        stateLock.unlock()
        stream?.stopCapture { _ in }
        eventsContinuation.yield(.state(.self, .waiting))
        eventsContinuation.yield(.state(.other, .waiting))
    }

    @MainActor
    func finish() {
        stop()
        continuation.finish()
        eventsContinuation.finish()
    }

    /// Reabre o mic sem AEC. É chamado automaticamente uma vez quando recebemos
    /// apenas zero digital e também fica disponível pelo indicador da UI.
    @MainActor
    func restartMicWithoutAEC() throws {
        eventsContinuation.yield(.state(.self, .recovering))
        if micRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            micRunning = false
        }
        let input = engine.inputNode
        if input.isVoiceProcessingEnabled {
            try input.setVoiceProcessingEnabled(false)
            engine.mainMixerNode.outputVolume = 1
        }
        signalMonitor.reset(.self)
        try startMic(echoCancellation: false)
    }

    @MainActor
    func restartSystemCapture() async {
        setSystemDesired(true)
        systemRecoveryTask?.cancel()
        systemRecoveryTask = nil
        systemRecoveryAttempt = 0
        eventsContinuation.yield(.state(.other, .recovering))
        do {
            try await startSystem()
        } catch {
            log.error("Falha ao recuperar captura de sistema: \(error.localizedDescription, privacy: .public)")
            scheduleSystemRecovery()
        }
    }

    // MARK: - Mic (AVAudioEngine)

    private func startMic(echoCancellation: Bool) throws {
        guard !micRunning else { return }
        let input = engine.inputNode

        // AEC (experimental): remove do mic o áudio dos alto-falantes (voz do
        // interlocutor). O nó VPIO só PROCESSA se o grafo de render estiver ativo —
        // por isso conectamos input→mixer com o output MUDO (senão o processo trava,
        // como no bug anterior). Sem fones, isto evita o eco marcado como "self".
        if echoCancellation {
            do {
                try input.setVoiceProcessingEnabled(true)
                let mixer = engine.mainMixerNode
                engine.connect(input, to: mixer, format: input.outputFormat(forBus: 0))
                mixer.outputVolume = 0            // não tocar o mic de volta (sem feedback)
                _ = engine.outputNode             // garante o nó de saída no grafo
                log.info("AEC (voice processing) ativado com grafo duplex")
            } catch {
                log.error("AEC indisponível, seguindo sem: \(error.localizedDescription, privacy: .public)")
            }
        }

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw CaptureError.noMicFormat
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, continuation] buffer, _ in
            guard let copy = buffer.deepCopy() else { return }
            self?.observeSignal(in: copy, source: .self)
            continuation.yield(AudioChunk(source: .self, buffer: copy))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            throw error
        }
        micRunning = true
        log.info("Mic iniciado @ \(format.sampleRate, privacy: .public) Hz (AEC: \(echoCancellation, privacy: .public))")
    }

    // MARK: - Sistema (ScreenCaptureKit)

    private func startSystem() async throws {
        if isSystemActive { return }
        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureError.screenCapturePermissionDenied
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        // Filtro por display inteiro; áudio de sistema é capturado independentemente
        // de janelas. Excluímos nada — queremos todo o áudio de saída.
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        // No modo treino, capturamos o próprio app (o TTS do entrevistador) como `other`.
        config.excludesCurrentProcessAudio = !captureOwnProcess
        config.sampleRate = 48_000
        config.channelCount = 1
        // Vídeo mínimo (SCStream exige config de vídeo; mantemos 2x2 e ignoramos frames).
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: scQueue)
        // Alguns setups só entregam áudio se houver também um output de vídeo ativo;
        // registramos e descartamos os frames (§ ver didOutputSampleBuffer).
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: scQueue)
        try await stream.startCapture()
        let keepRunning = stateLock.withLock {
            if systemDesired {
                self.scStream = stream
                systemRunning = true
            }
            return systemDesired
        }
        guard keepRunning else {
            try? await stream.stopCapture()
            return
        }
        systemRecoveryAttempt = 0
        signalMonitor.reset(.other)
        eventsContinuation.yield(.state(.other, .active))
        log.info("Captura de sistema (ScreenCaptureKit) iniciada")
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let pcm = AudioConverter.pcmBuffer(from: sampleBuffer) else { return }
        observeSignal(in: pcm, source: .other)
        continuation.yield(AudioChunk(source: .other, buffer: pcm))
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("SCStream parou com erro: \(error.localizedDescription, privacy: .public)")
        stateLock.lock()
        guard scStream === stream else {
            stateLock.unlock()
            return
        }
        scStream = nil
        systemRunning = false
        let shouldRecover = systemDesired
        stateLock.unlock()
        eventsContinuation.yield(.state(.other, shouldRecover ? .recovering : .waiting))
        guard shouldRecover else { return }
        Task { @MainActor [weak self] in self?.scheduleSystemRecovery() }
    }

    // MARK: - Saúde e autorrecuperação

    private func setSystemDesired(_ desired: Bool) {
        stateLock.lock(); systemDesired = desired; stateLock.unlock()
    }

    private func wantsSystemCapture() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return systemDesired
    }

    @MainActor
    private func scheduleSystemRecovery() {
        guard wantsSystemCapture(), systemRecoveryTask == nil else { return }
        systemRecoveryAttempt += 1
        guard systemRecoveryAttempt <= 5 else {
            eventsContinuation.yield(.state(.other, .unavailable))
            return
        }
        eventsContinuation.yield(.state(.other, .recovering))
        let delay = min(Double(1 << (systemRecoveryAttempt - 1)), 8)
        systemRecoveryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard let self, self.wantsSystemCapture() else { return }
            self.systemRecoveryTask = nil
            do {
                try await self.startSystem()
            } catch {
                self.log.error("Retry de captura de sistema falhou: \(error.localizedDescription, privacy: .public)")
                self.scheduleSystemRecovery()
            }
        }
    }

    private func observeSignal(in buffer: AVAudioPCMBuffer, source: Speaker) {
        for event in signalMonitor.observe(buffer, source: source) {
            eventsContinuation.yield(event)
        }
    }

    enum CaptureError: LocalizedError {
        case noMicFormat
        case noDisplay
        case screenCapturePermissionDenied

        var errorDescription: String? {
            switch self {
            case .noMicFormat: return "Formato de microfone indisponível."
            case .noDisplay: return "Nenhum display disponível para captura de áudio de sistema."
            case .screenCapturePermissionDenied:
                return "Permissão de Tela e Áudio do Sistema não concedida para esta cópia do CueMe."
            }
        }
    }
}

extension AVAudioPCMBuffer {
    /// Cópia profunda — o buffer do tap é reutilizado pela engine após o callback.
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        copy.frameLength = frameLength
        let channels = Int(format.channelCount)

        if let src = floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<channels {
                dst[ch].update(from: src[ch], count: Int(frameLength))
            }
        } else if let src = int16ChannelData, let dst = copy.int16ChannelData {
            for ch in 0..<channels {
                dst[ch].update(from: src[ch], count: Int(frameLength))
            }
        } else if let src = int32ChannelData, let dst = copy.int32ChannelData {
            for ch in 0..<channels {
                dst[ch].update(from: src[ch], count: Int(frameLength))
            }
        } else {
            return nil
        }
        return copy
    }
}
