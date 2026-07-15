import Foundation

struct SessionNote: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var timeOffset: TimeInterval
    var text: String
    let createdAt: Date

    init(id: UUID = UUID(), timeOffset: TimeInterval, text: String, createdAt: Date = Date()) {
        self.id = id
        self.timeOffset = max(0, timeOffset)
        self.text = text
        self.createdAt = createdAt
    }
}

struct SessionTakeaway: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var text: String
    var isDone: Bool
    var evidence: [MemoryEvidence]
    var confidence: Double?
    var assignee: String?
    var dueAt: Date?
    var createdInSessionID: UUID?
    let createdAt: Date

    init(
        id: UUID = UUID(), text: String, isDone: Bool = false, createdAt: Date = Date(),
        evidence: [MemoryEvidence] = [], confidence: Double? = nil, assignee: String? = nil,
        dueAt: Date? = nil, createdInSessionID: UUID? = nil
    ) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.createdAt = createdAt
        self.evidence = evidence
        self.confidence = confidence
        self.assignee = assignee
        self.dueAt = dueAt
        self.createdInSessionID = createdInSessionID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        isDone = try c.decode(Bool.self, forKey: .isDone)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        evidence = try c.decodeIfPresent([MemoryEvidence].self, forKey: .evidence) ?? []
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        assignee = try c.decodeIfPresent(String.self, forKey: .assignee)
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        createdInSessionID = try c.decodeIfPresent(UUID.self, forKey: .createdInSessionID)
    }
}

struct MeetingReviewItem: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var text: String
    var evidence: [MemoryEvidence]
    var confidence: Double?
    var createdInSessionID: UUID?
    var supersedesID: UUID?

    init(
        id: UUID = UUID(), text: String, evidence: [MemoryEvidence] = [],
        confidence: Double? = nil, createdInSessionID: UUID? = nil, supersedesID: UUID? = nil
    ) {
        self.id = id
        self.text = text
        self.evidence = evidence
        self.confidence = confidence
        self.createdInSessionID = createdInSessionID
        self.supersedesID = supersedesID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        evidence = try c.decodeIfPresent([MemoryEvidence].self, forKey: .evidence) ?? []
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
        createdInSessionID = try c.decodeIfPresent(UUID.self, forKey: .createdInSessionID)
        supersedesID = try c.decodeIfPresent(UUID.self, forKey: .supersedesID)
    }
}

struct MemoryEvidence: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    var turnID: UUID?
    var timestamp: TimeInterval
    var quote: String

    init(id: UUID = UUID(), turnID: UUID? = nil, timestamp: TimeInterval, quote: String) {
        self.id = id
        self.turnID = turnID
        self.timestamp = max(0, timestamp)
        self.quote = quote
    }
}

struct MeetingReview: Codable, Sendable, Hashable {
    var decisions: [MeetingReviewItem]
    var openQuestions: [MeetingReviewItem]
    var followUp: String

    init(
        decisions: [MeetingReviewItem] = [],
        openQuestions: [MeetingReviewItem] = [],
        followUp: String = ""
    ) {
        self.decisions = decisions
        self.openQuestions = openQuestions
        self.followUp = followUp
    }

    static let empty = MeetingReview()
    var isEmpty: Bool {
        decisions.isEmpty && openQuestions.isEmpty
            && followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct SessionReviewExtraction: Sendable, Equatable {
    var minutes: MeetingMinutes
    var takeaways: [SessionTakeaway]
    var review: MeetingReview
}

enum FollowUpFormat: String, CaseIterable, Sendable, Identifiable {
    case email, slack, minutes
    var id: String { rawValue }

    var label: String {
        switch self {
        case .email: return "E-mail"
        case .slack: return "Slack"
        case .minutes: return "Ata"
        }
    }

    var icon: String {
        switch self {
        case .email: return "envelope"
        case .slack: return "bubble.left.and.bubble.right"
        case .minutes: return "doc.text"
        }
    }

    var request: String {
        switch self {
        case .email:
            return "Escreva um e-mail de follow-up curto com decisões, ações e dúvidas abertas."
        case .slack:
            return "Escreva uma atualização curta para Slack com decisões, responsáveis e próximos passos."
        case .minutes:
            return "Gere uma ata formal em Markdown com resumo, assuntos, decisões, ações e questões abertas."
        }
    }
}

enum SessionArtifactKind: String, Codable, Sendable, Hashable {
    case review
    case summary
    case takeaways
    case answer
    case custom
}

struct SessionArtifact: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var kind: SessionArtifactKind
    var title: String
    var body: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: SessionArtifactKind,
        title: String,
        body: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}
