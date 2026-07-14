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
    let createdAt: Date

    init(id: UUID = UUID(), text: String, isDone: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.createdAt = createdAt
    }
}

enum SessionArtifactKind: String, Codable, Sendable, Hashable {
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
