import AVFoundation

/// Buffer de áudio taggeado com a origem (locutor conhecido por origem) e o
/// instante de captura (pra sincronizar a gravação com a transcrição).
struct AudioChunk: @unchecked Sendable {
    let source: Speaker
    let buffer: AVAudioPCMBuffer
    let ts: Date

    init(source: Speaker, buffer: AVAudioPCMBuffer, ts: Date = Date()) {
        self.source = source
        self.buffer = buffer
        self.ts = ts
    }
}
