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

struct DiagnosticAggregate: Codable, Sendable, Hashable {
    var count = 0
    var totalDurationMs: Int64 = 0
    var durationSamples = 0
    var maxDurationMs: Int64 = 0
    var durationValues: [Int64]? = []

    mutating func record(durationMs: Int64?) {
        count += 1
        guard let durationMs else { return }
        totalDurationMs += durationMs
        durationSamples += 1
        maxDurationMs = max(maxDurationMs, durationMs)
        durationValues?.append(durationMs)
        if let count = durationValues?.count, count > 1_000 {
            durationValues?.removeFirst(count - 1_000)
        }
    }
}

struct SessionDiagnostics: Codable, Sendable, Hashable {
    var events: [DiagnosticEvent] = []
    private var aggregates: [String: DiagnosticAggregate] = [:]
    private var kindCounts: [DiagnosticEvent.Kind: Int] = [:]

    mutating func record(_ event: DiagnosticEvent) {
        events.append(event)
        aggregates[event.name, default: .init()].record(durationMs: event.durationMs)
        kindCounts[event.kind, default: 0] += 1
        if events.count > 500 { events.removeFirst(events.count - 500) }
    }

    func count(_ name: String) -> Int {
        aggregates[name]?.count ?? events.lazy.filter { $0.name == name }.count
    }

    func averageMs(_ name: String) -> Int64? {
        if let aggregate = aggregates[name], aggregate.durationSamples > 0 {
            return aggregate.totalDurationMs / Int64(aggregate.durationSamples)
        }
        let values = events.lazy.filter { $0.name == name }.compactMap(\.durationMs)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Int64(values.count)
    }

    func count(kind: DiagnosticEvent.Kind) -> Int {
        kindCounts[kind] ?? events.lazy.filter { $0.kind == kind }.count
    }

    func durationValues(_ name: String) -> [Int64] {
        aggregates[name]?.durationValues ?? events.lazy.filter { $0.name == name }.compactMap(\.durationMs)
    }

    private enum CodingKeys: String, CodingKey { case events, aggregates, kindCounts }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decodeIfPresent([DiagnosticEvent].self, forKey: .events) ?? []
        aggregates = try container.decodeIfPresent([String: DiagnosticAggregate].self, forKey: .aggregates) ?? [:]
        kindCounts = try container.decodeIfPresent([DiagnosticEvent.Kind: Int].self, forKey: .kindCounts) ?? [:]
        if aggregates.isEmpty {
            for event in events { aggregates[event.name, default: .init()].record(durationMs: event.durationMs) }
        }
        if kindCounts.isEmpty {
            for event in events { kindCounts[event.kind, default: 0] += 1 }
        }
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
    private var startedAt: Date
    private var lastSummaryAt: Date?

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    mutating func registerFinalTurn(at now: Date = Date()) -> Bool {
        finalTurnCount += 1
        let newTurns = finalTurnCount - summarizedTurnCount
        if lastSummaryAt == nil {
            return newTurns >= 8 && now.timeIntervalSince(startedAt) >= 45
        }
        return newTurns >= 12 && now.timeIntervalSince(lastSummaryAt!) >= 120
    }

    mutating func markSummarized(at now: Date = Date(), turnCount: Int? = nil) {
        summarizedTurnCount = min(turnCount ?? finalTurnCount, finalTurnCount)
        lastSummaryAt = now
    }
    var hasUnsummarizedTurns: Bool { finalTurnCount > summarizedTurnCount }
}

enum CoachTriggerPolicy {
    static func fingerprint(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func shouldTrigger(
        text: String,
        mode: Mode,
        speakerCertain: Bool,
        now: Date = Date(),
        lastTriggeredAt: Date?,
        lastFingerprint: String?
    ) -> Bool {
        guard !mode.isPassive, speakerCertain else { return false }
        let normalized = fingerprint(text)
        guard normalized.split(separator: " ").count >= 4,
              normalized != lastFingerprint else { return false }

        let directQuestion = looksLikeQuestion(text)
            || ["concorda", "o que você acha", "alguma sugestão", "faz sentido", "pode ser"]
                .contains(where: normalized.contains)
        let meetingMoment = [
            "ficou combinado", "próximo passo", "responsável", "prazo", "risco",
            "dependência", "bloqueio", "decisão", "vamos fazer", "a gente precisa",
        ].contains(where: normalized.contains)

        let cooldown: TimeInterval
        switch mode {
        case .interview: cooldown = directQuestion ? 5 : 30
        case .sales, .difficult: cooldown = directQuestion ? 10 : 30
        case .meeting, .custom: cooldown = directQuestion ? 15 : 45
        case .recording: return false
        }
        if let lastTriggeredAt, now.timeIntervalSince(lastTriggeredAt) < cooldown { return false }

        switch mode {
        case .interview, .sales, .difficult: return directQuestion
        case .meeting: return directQuestion || meetingMoment
        case .custom: return directQuestion || meetingMoment
        case .recording: return false
        }
    }

    private static func looksLikeQuestion(_ value: String) -> Bool {
        if value.contains("?") { return true }
        let lower = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let starters = [
            "what", "why", "how", "when", "where", "which", "who", "could you",
            "can you", "tell me", "walk me", "describe", "would you", "do you",
            "have you", "o que", "por que", "como", "quando", "onde", "qual",
            "quem", "me conta", "me fala", "descreva", "você pode",
        ]
        return starters.contains(where: lower.hasPrefix)
    }
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
        case .recording: return "FATO → DECISÃO → RESPONSÁVEL"
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
