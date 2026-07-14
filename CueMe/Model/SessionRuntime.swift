import Foundation

/// Metadata-only session telemetry. It intentionally excludes transcript text,
/// audio samples, credentials, prompts, and provider responses.
struct DiagnosticEvent: Codable, Sendable, Hashable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case session, capture, transcription, coach, summary, recovery, error
    }

    let id: UUID
    let at: Date
    let kind: Kind
    let name: String
    let speaker: Speaker?
    let durationMs: Int64?
    let detail: String?

    init(
        id: UUID = UUID(),
        at: Date = Date(),
        kind: Kind,
        name: String,
        speaker: Speaker? = nil,
        durationMs: Int64? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.name = name
        self.speaker = speaker
        self.durationMs = durationMs
        self.detail = detail
    }
}

struct SessionDiagnostics: Codable, Sendable, Hashable {
    var events: [DiagnosticEvent] = []

    mutating func record(_ event: DiagnosticEvent) {
        events.append(event)
        if events.count > 500 { events.removeFirst(events.count - 500) }
    }

    func count(_ name: String) -> Int { events.lazy.filter { $0.name == name }.count }

    func averageMs(_ name: String) -> Int64? {
        let values = events.lazy.filter { $0.name == name }.compactMap(\.durationMs)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Int64(values.count)
    }
}

/// Detects an actionable, stable partial before the speech recognizer emits a
/// final. Repeated normalized text is considered stable; each utterance fires once.
struct SpeculativeTurnDetector: Sendable {
    private(set) var lastText = ""
    private(set) var repetitions = 0
    private(set) var lastTriggered = ""

    mutating func observe(_ text: String, looksActionable: (String) -> Bool) -> Bool {
        let normalized = Self.normalize(text)
        guard normalized.split(separator: " ").count >= 4 else { return false }
        if normalized == lastText {
            repetitions += 1
        } else {
            lastText = normalized
            repetitions = 1
        }
        guard repetitions >= 2, normalized != lastTriggered, looksActionable(text) else { return false }
        lastTriggered = normalized
        return true
    }

    mutating func finalize() { lastText = ""; repetitions = 0 }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct SummarySchedulePolicy: Sendable {
    private(set) var finalTurnCount = 0
    private(set) var summarizedTurnCount = 0

    mutating func registerFinalTurn() -> Bool {
        finalTurnCount += 1
        let threshold = summarizedTurnCount == 0 ? 3 : 3
        return finalTurnCount - summarizedTurnCount >= threshold
    }

    mutating func markSummarized() { summarizedTurnCount = finalTurnCount }
    var hasUnsummarizedTurns: Bool { finalTurnCount > summarizedTurnCount }
}

enum LatencyFallback {
    static func guide(for text: String, mode: Mode) -> String {
        let lower = text.lowercased()
        if lower.contains("why") || lower.contains("por que") {
            return "MOTIVO → EVIDÊNCIA → IMPACTO"
        }
        if lower.contains("how") || lower.contains("como") {
            return "PLANO → AÇÃO → RESULTADO"
        }
        switch mode {
        case .interview: return "CONTEXTO → AÇÃO → RESULTADO"
        case .sales: return "DOR → VALOR → PRÓXIMO PASSO"
        case .difficult: return "FATO → SENTIMENTO → PEDIDO"
        case .custom: return "PONTO → PROVA → CONCLUSÃO"
        case .meeting: return "FATO → DECISÃO → RESPONSÁVEL"
        }
    }
}

enum PreflightCheck: String, CaseIterable, Sendable, Identifiable {
    case microphone, systemAudio, coach
    var id: String { rawValue }
    var label: String {
        switch self {
        case .microphone: return "MIC"
        case .systemAudio: return "CALL"
        case .coach: return "COACH"
        }
    }
}

enum PreflightStatus: Sendable, Equatable {
    case idle, checking, passed, failed
}
