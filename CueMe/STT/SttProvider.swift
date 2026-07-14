import Foundation
import AVFoundation

/// Configuração de uma sessão de STT para UM fluxo (mic OU sistema).
struct SttConfig: Sendable {
    var speaker: Speaker
    var localeIdentifier: String   // ex.: "en-US"
    var keyterms: [String]         // usado por providers de nuvem (ignorado pelo nativo)
    var replacements: [String: String] = [:]
}

/// Protocolo plugável de STT. Cada sessão transcreve um fluxo e emite eventos
/// já taggeados com o locutor (pela origem do stream).
protocol SttSession: Actor {
    /// Eventos de transcrição (partials/finals) deste fluxo.
    nonisolated var events: AsyncStream<TranscriptEvent> { get }
    func start() async throws
    func feed(_ buffer: AVAudioPCMBuffer)
    func finish() async
}

protocol SttProvider: Sendable {
    func makeSession(config: SttConfig) -> any SttSession
}

struct NativeSttProvider: SttProvider {
    func makeSession(config: SttConfig) -> any SttSession {
        NativeTranscriber(config: config)
    }
}

struct DeepgramSttProvider: SttProvider {
    let apiKey: String

    func makeSession(config: SttConfig) -> any SttSession {
        DeepgramTranscriber(config: config, apiKey: apiKey)
    }
}

enum SttProviderFactory {
    static func make(source: SttSource, deepgramAPIKey: String?) throws -> any SttProvider {
        switch source {
        case .native:
            return NativeSttProvider()
        case .deepgram:
            let key = deepgramAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !key.isEmpty else { throw DeepgramError.missingAPIKey }
            return DeepgramSttProvider(apiKey: key)
        }
    }
}

enum SttError: LocalizedError {
    case localeUnsupported(String)
    case noAudioFormat
    case assetInstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .localeUnsupported(let id):
            return "Idioma \(id) não é suportado on-device pelo SpeechTranscriber."
        case .noAudioFormat:
            return "Não foi possível obter um formato de áudio compatível com o transcritor."
        case .assetInstallFailed(let msg):
            return "Falha ao baixar o modelo de idioma: \(msg)"
        }
    }
}
