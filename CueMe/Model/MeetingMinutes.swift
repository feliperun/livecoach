import Foundation

struct MeetingTopic: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var title: String
    var summary: String
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, summary: String, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.summary = summary
        self.updatedAt = updatedAt
    }
}

struct MeetingMinutes: Codable, Sendable, Hashable {
    var overview: String
    var topics: [MeetingTopic]
    var updatedAt: Date?

    init(overview: String = "", topics: [MeetingTopic] = [], updatedAt: Date? = nil) {
        self.overview = overview
        self.topics = topics
        self.updatedAt = updatedAt
    }

    static let empty = MeetingMinutes()
    var isEmpty: Bool { overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && topics.isEmpty }

    static func parse(modelOutput raw: String, preserving existing: MeetingMinutes = .empty) -> MeetingMinutes? {
        struct Payload: Decodable {
            struct Topic: Decodable { let title: String; let summary: String }
            let overview: String
            let topics: [Topic]
        }
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = value.firstIndex(of: "{"), let end = value.lastIndex(of: "}") else { return nil }
        value = String(value[start...end])
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(value.utf8)) else { return nil }
        let oldByTitle = Dictionary(uniqueKeysWithValues: existing.topics.map {
            ($0.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current), $0)
        })
        let topics = payload.topics.prefix(12).compactMap { topic -> MeetingTopic? in
            let title = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = topic.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !summary.isEmpty else { return nil }
            let key = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return MeetingTopic(id: oldByTitle[key]?.id ?? UUID(), title: title, summary: summary)
        }
        let overview = payload.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !overview.isEmpty || !topics.isEmpty else { return nil }
        return MeetingMinutes(overview: overview, topics: topics, updatedAt: Date())
    }
}
