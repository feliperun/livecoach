import AVFoundation
import OSLog

/// Grava o áudio original da sessão em DOIS arquivos sincronizados — um por
/// locutor (self/other) — pra reouvir depois junto com a transcrição.
///
/// Cada chunk chega com o instante de captura (`ts`). Como os dois lados
/// disparam de forma independente e nem sempre falam ao mesmo tempo, cada
/// arquivo recebe SILÊNCIO até a posição de frame correspondente ao tempo
/// decorrido desde o início da gravação — assim os dois arquivos ficam
/// alinhados ao mesmo relógio de parede e tocam em sincronia (ADR 0012).
actor MeetingRecorder {
    private let log = Logger(subsystem: "CueMe", category: "MeetingRecorder")

    static let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    private var selfFile: AVAudioFile?
    private var otherFile: AVAudioFile?
    private let selfConverter = AudioConverter(outputFormat: MeetingRecorder.format)
    private let otherConverter = AudioConverter(outputFormat: MeetingRecorder.format)

    private var recordingStart: Date?
    private var selfFrames: AVAudioFramePosition = 0
    private var otherFrames: AVAudioFramePosition = 0
    private var writeFailures = 0

    struct HealthSnapshot: Sendable, Equatable {
        let framesWritten: Int64
        let writeFailures: Int
    }

    @discardableResult
    func start(directory: URL) throws -> Date {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = Self.format.settings
        selfFile = try AVAudioFile(
            forWriting: directory.appendingPathComponent(MeetingRecording.selfFilename),
            settings: settings, commonFormat: .pcmFormatInt16, interleaved: true
        )
        otherFile = try AVAudioFile(
            forWriting: directory.appendingPathComponent(MeetingRecording.otherFilename),
            settings: settings, commonFormat: .pcmFormatInt16, interleaved: true
        )
        let startedAt = Date()
        recordingStart = startedAt
        selfFrames = 0
        otherFrames = 0
        writeFailures = 0
        log.info("Gravação iniciada em \(directory.lastPathComponent, privacy: .public)")
        return startedAt
    }

    func ingest(_ chunk: AudioChunk) {
        guard let start = recordingStart else { return }
        switch chunk.source {
        case .self:
            guard let file = selfFile, let converted = selfConverter.convert(chunk.buffer) else { return }
            write(converted, into: file, framesWritten: &selfFrames, chunkTs: chunk.ts, start: start)
        case .other:
            guard let file = otherFile, let converted = otherConverter.convert(chunk.buffer) else { return }
            write(converted, into: file, framesWritten: &otherFrames, chunkTs: chunk.ts, start: start)
        }
    }

    /// Encerra a gravação e devolve a duração total (s), ou nil se nada foi gravado.
    func stop() -> TimeInterval? {
        selfFile = nil
        otherFile = nil
        let frames = max(selfFrames, otherFrames)
        recordingStart = nil
        guard frames > 0 else { return nil }
        return Double(frames) / Self.format.sampleRate
    }

    func healthSnapshot() -> HealthSnapshot {
        .init(framesWritten: Int64(max(selfFrames, otherFrames)), writeFailures: writeFailures)
    }

    // MARK: - Escrita com preenchimento de silêncio (mantém sincronia)

    private func write(
        _ buffer: AVAudioPCMBuffer,
        into file: AVAudioFile,
        framesWritten: inout AVAudioFramePosition,
        chunkTs: Date,
        start: Date
    ) {
        let target = AVAudioFramePosition(chunkTs.timeIntervalSince(start) * Self.format.sampleRate)
        if target > framesWritten {
            padSilence(into: file, frameCount: target - framesWritten)
            framesWritten = target
        }
        do {
            try file.write(from: buffer)
            framesWritten += AVAudioFramePosition(buffer.frameLength)
        } catch {
            writeFailures += 1
            log.error("Falha ao gravar áudio: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func padSilence(into file: AVAudioFile, frameCount: AVAudioFramePosition) {
        var remaining = frameCount
        let step: AVAudioFrameCount = 80_000   // ~5s por bloco, evita alocar demais em silêncios longos
        while remaining > 0 {
            let n = AVAudioFrameCount(min(AVAudioFramePosition(step), remaining))
            guard let silence = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: n) else { return }
            silence.frameLength = n   // memória zerada = silêncio
            do {
                try file.write(from: silence)
                remaining -= AVAudioFramePosition(n)
            } catch {
                writeFailures += 1
                log.error("Falha ao preencher silêncio: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
    }
}

/// Metadados + localização dos arquivos de uma gravação (sem caminho absoluto
/// persistido — reconstruído a partir do id da sessão, pra manter o export
/// portável entre máquinas).
enum MeetingRecording {
    static let selfFilename = "self.caf"
    static let otherFilename = "other.caf"

    static func directory(for sessionID: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("CueMe/recordings/\(sessionID.uuidString)", isDirectory: true)
    }

    static func selfURL(for sessionID: UUID) -> URL { directory(for: sessionID).appendingPathComponent(selfFilename) }
    static func otherURL(for sessionID: UUID) -> URL { directory(for: sessionID).appendingPathComponent(otherFilename) }

    static func exists(for sessionID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: selfURL(for: sessionID).path)
            || FileManager.default.fileExists(atPath: otherURL(for: sessionID).path)
    }

    static func delete(for sessionID: UUID) {
        try? FileManager.default.removeItem(at: directory(for: sessionID))
    }
}
