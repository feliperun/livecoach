import Foundation

/// Quem falou. Conhecido pela origem do stream (mic = self, sistema = other).
enum Speaker: String, Codable, Sendable, Hashable {
    case `self`
    case other

    var label: String {
        switch self {
        case .self: return "Você"
        case .other: return "Interlocutor"
        }
    }
}

/// Evento cru vindo de um `SttProvider`, publicado no `TranscriptBus`.
struct TranscriptEvent: Identifiable, Sendable, Hashable {
    let id: UUID
    let speaker: Speaker
    var text: String
    var isFinal: Bool
    var isEndOfTurn: Bool
    let ts: Date

    init(
        id: UUID = UUID(),
        speaker: Speaker,
        text: String,
        isFinal: Bool,
        isEndOfTurn: Bool,
        ts: Date = Date()
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.isFinal = isFinal
        self.isEndOfTurn = isEndOfTurn
        self.ts = ts
    }
}

/// Um turno solidificado (texto final de um locutor), base para janela rolante.
struct Turn: Identifiable, Sendable, Hashable {
    let id: UUID
    let speaker: Speaker
    var text: String
    let ts: Date

    init(id: UUID = UUID(), speaker: Speaker, text: String, ts: Date = Date()) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.ts = ts
    }
}

/// Linha renderizada no painel de transcript (original + tradução opcional).
struct TranscriptLine: Identifiable, Sendable, Hashable, Codable {
    let id: UUID
    let speaker: Speaker
    var text: String
    var translation: String?
    var isFinal: Bool
    let ts: Date
    var sourceTurnID: UUID?
    var originalText: String?
    var editedAt: Date?

    init(
        id: UUID = UUID(),
        speaker: Speaker,
        text: String,
        translation: String? = nil,
        isFinal: Bool,
        ts: Date = Date(),
        sourceTurnID: UUID? = nil,
        originalText: String? = nil,
        editedAt: Date? = nil
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.translation = translation
        self.isFinal = isFinal
        self.ts = ts
        self.sourceTurnID = sourceTurnID
        self.originalText = originalText
        self.editedAt = editedAt
    }

    var wasEdited: Bool { originalText != nil && editedAt != nil }

    mutating func applyCorrection(_ corrected: String, at date: Date = Date()) {
        let value = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != text else { return }
        if originalText == nil { originalText = text }
        text = value
        editedAt = date
    }
}

enum CoachKind: String, Sendable, Codable {
    case answer      // sugestão de resposta ao interlocutor
    case correction  // correção do que o usuário disse
    case manual      // resposta a pergunta digitada
}

enum Severity: String, Sendable, Codable {
    case info
    case warn
}

/// Card de coaching mostrado no painel direito.
struct CoachCard: Identifiable, Sendable, Codable {
    let id: UUID
    var guidePT: String            // guia sempre no idioma nativo
    var sayConversation: String?   // frase no idioma da conversa (nil se == nativo)
    var sayNative: String          // mesma frase no idioma nativo
    var keytermsConversation: [String]
    var kind: CoachKind
    var severity: Severity
    var isStreaming: Bool
    let ts: Date

    init(
        id: UUID = UUID(),
        guidePT: String = "",
        sayConversation: String? = nil,
        sayNative: String = "",
        keytermsConversation: [String] = [],
        kind: CoachKind = .answer,
        severity: Severity = .info,
        isStreaming: Bool = true,
        ts: Date = Date()
    ) {
        self.id = id
        self.guidePT = guidePT
        self.sayConversation = sayConversation
        self.sayNative = sayNative
        self.keytermsConversation = keytermsConversation
        self.kind = kind
        self.severity = severity
        self.isStreaming = isStreaming
        self.ts = ts
    }

    var hasContent: Bool {
        !guidePT.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(sayConversation ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !sayNative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum SessionState: Sendable, Equatable {
    case idle
    case preparing
    case running
    case stopping
    case paused
    case error(String)
}

/// Saúde de cada canal de captura. A UI mostra apenas um sinal visual curto;
/// detalhes ficam no tooltip/log para não disputar atenção durante a conversa.
enum CaptureChannelState: Sendable, Equatable {
    case waiting
    case active
    case silent
    case recovering
    case unavailable
}

/// Eventos de baixo volume emitidos pela captura para manter a UI honesta.
enum AudioCaptureEvent: Sendable {
    case level(Speaker, Float)
    case state(Speaker, CaptureChannelState)
}

/// Resultado atômico do teardown. O início do áudio é diferente do clique em
/// "Iniciar" e precisa acompanhar a duração para o replay ficar sincronizado.
struct SessionStopResult: Sendable {
    var audioDuration: TimeInterval?
    var recordingStartedAt: Date?

    static let empty = SessionStopResult(audioDuration: nil, recordingStartedAt: nil)
}

/// Delta emitido pela raia de coaching enquanto o modelo faz streaming.
struct CoachDelta: Sendable {
    var text: String
}
