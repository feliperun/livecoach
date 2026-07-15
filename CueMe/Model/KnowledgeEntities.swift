import Foundation

struct KnowledgeProject: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var name: String
    var summary: String
    var createdAt: Date
    var archived: Bool

    init(id: UUID = UUID(), name: String, summary: String = "", createdAt: Date = Date(), archived: Bool = false) {
        self.id = id
        self.name = name
        self.summary = summary
        self.createdAt = createdAt
        self.archived = archived
    }
}

struct KnowledgePerson: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var name: String
    var aliases: [String]
    var role: String?
    var organization: String?

    init(id: UUID = UUID(), name: String, aliases: [String] = [], role: String? = nil, organization: String? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.role = role
        self.organization = organization
    }
}

struct ProjectTimelineEntry: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable { case meeting, decision, action, question }
    let id: String
    let sessionID: UUID
    let date: Date
    let kind: Kind
    let title: String
    let detail: String
}

enum KnowledgeEntityStore {
    private struct Payload: Codable { var projects: [KnowledgeProject]; var people: [KnowledgePerson] }

    private static var url: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CueMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("knowledge-entities.json")
    }

    static func load() -> (projects: [KnowledgeProject], people: [KnowledgePerson]) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let payload = try? decoder.decode(Payload.self, from: data) else { return ([], []) }
        return (payload.projects, payload.people)
    }

    static func save(projects: [KnowledgeProject], people: [KnowledgePerson]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Payload(projects: projects, people: people)).write(to: url, options: .atomic)
    }

    static func timeline(projectID: UUID, records: [SessionRecord]) -> [ProjectTimelineEntry] {
        records.filter { $0.projectID == projectID }.flatMap { record in
            var entries = [ProjectTimelineEntry(
                id: "meeting-\(record.id)", sessionID: record.id, date: record.startedAt,
                kind: .meeting, title: record.title, detail: record.minutes.overview
            )]
            entries += record.review.decisions.map {
                .init(id: "decision-\($0.id)", sessionID: record.id, date: record.startedAt,
                      kind: .decision, title: "Decisão", detail: $0.text)
            }
            entries += record.takeaways.map {
                .init(id: "action-\($0.id)", sessionID: record.id, date: record.startedAt,
                      kind: .action, title: $0.isDone ? "Ação concluída" : "Ação pendente", detail: $0.text)
            }
            entries += record.review.openQuestions.map {
                .init(id: "question-\($0.id)", sessionID: record.id, date: record.startedAt,
                      kind: .question, title: "Questão em aberto", detail: $0.text)
            }
            return entries
        }.sorted { $0.date > $1.date }
    }
}
