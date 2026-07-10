import AVFoundation
import ScreenCaptureKit
import OSLog

/// Captura nativa dos dois lados:
///  - mic do usuário via `AVAudioEngine` (tag `.self`)
///  - áudio do sistema (interlocutor) via `ScreenCaptureKit` (tag `.other`)
///
/// Regra dos callbacks de áudio: fazer o mínimo. Aqui só empacotam o buffer e
/// entregam ao mundo async via `AsyncStream.Continuation`.
final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let log = Logger(subsystem: "LiveCopilot", category: "AudioCapture")

    let chunks: AsyncStream<AudioChunk>
    private let continuation: AsyncStream<AudioChunk>.Continuation

    private let engine = AVAudioEngine()
    private var scStream: SCStream?
    private let scQueue = DispatchQueue(label: "LiveCopilot.SCStreamOutput")

    private var micRunning = false
    private var systemRunning = false

    /// Captura de sistema (interlocutor) ativa? Lido pela UI.
    var isSystemActive: Bool { systemRunning }

    override init() {
        var cont: AsyncStream<AudioChunk>.Continuation!
        self.chunks = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { cont = $0 }
        self.continuation = cont
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

    func start(includeSystem: Bool) async throws {
        try startMic()
        if includeSystem {
            do {
                try await startSystem()
            } catch {
                // Sistema é opcional: se a permissão de gravação de tela faltar,
                // seguimos só com o mic (mock interview de um lado).
                log.error("Falha ao iniciar captura de sistema: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop() {
        if micRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            micRunning = false
        }
        if let scStream {
            scStream.stopCapture { _ in }
            self.scStream = nil
            systemRunning = false
        }
    }

    func finish() {
        stop()
        continuation.finish()
    }

    // MARK: - Mic (AVAudioEngine)

    private func startMic() throws {
        guard !micRunning else { return }
        let input = engine.inputNode

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw CaptureError.noMicFormat
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [continuation] buffer, _ in
            guard let copy = buffer.deepCopy() else { return }
            continuation.yield(AudioChunk(source: .self, buffer: copy))
        }
        engine.prepare()
        try engine.start()
        micRunning = true
        log.info("Mic iniciado @ \(format.sampleRate, privacy: .public) Hz")
    }

    // MARK: - Sistema (ScreenCaptureKit)

    private func startSystem() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        // Filtro por display inteiro; áudio de sistema é capturado independentemente
        // de janelas. Excluímos nada — queremos todo o áudio de saída.
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true   // não capturar o próprio app
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
        self.scStream = stream
        systemRunning = true
        log.info("Captura de sistema (ScreenCaptureKit) iniciada")
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let pcm = AudioConverter.pcmBuffer(from: sampleBuffer) else { return }
        continuation.yield(AudioChunk(source: .other, buffer: pcm))
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("SCStream parou com erro: \(error.localizedDescription, privacy: .public)")
        systemRunning = false
    }

    enum CaptureError: LocalizedError {
        case noMicFormat
        case noDisplay

        var errorDescription: String? {
            switch self {
            case .noMicFormat: return "Formato de microfone indisponível."
            case .noDisplay: return "Nenhum display disponível para captura de áudio de sistema."
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
