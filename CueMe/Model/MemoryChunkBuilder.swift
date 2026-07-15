import Foundation

struct MemoryChunk: Sendable, Hashable {
    enum Kind: String, Sendable { case transcript, topic, decision, action, question, note, artifact }
    let id: String; let sessionID: UUID; let projectID: UUID?; let kind: Kind
    let startedAt: Date; let timestamp: TimeInterval?; let text: String
}

enum MemoryChunkBuilder {
    static func chunks(_ record: SessionRecord) -> [MemoryChunk] {
        var result: [MemoryChunk] = []
        let finals = record.transcript.filter(\.isFinal)
        for start in stride(from: 0, to: finals.count, by: 5) {
            let lines = Array(finals[start..<min(finals.count, start + 7)])
            guard let first = lines.first else { continue }
            let body = lines.map {
                "\(record.participantName(for: $0.speaker)): \($0.text)\($0.translation.map { " | \($0)" } ?? "")"
            }.joined(separator: "\n")
            result.append(.init(id: "transcript:\(record.id):\(start)", sessionID: record.id,
                projectID: record.projectID, kind: .transcript, startedAt: record.startedAt,
                timestamp: first.ts.timeIntervalSince(record.audioTimelineStart), text: body))
        }
        func append(_ id: String, _ kind: MemoryChunk.Kind, _ text: String, _ timestamp: TimeInterval? = nil) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            result.append(.init(id: id, sessionID: record.id, projectID: record.projectID,
                kind: kind, startedAt: record.startedAt, timestamp: timestamp, text: text))
        }
        record.minutes.topics.forEach { append("topic:\($0.id)", .topic, "\($0.title): \($0.summary)") }
        record.review.decisions.forEach { append("decision:\($0.id)", .decision, $0.text, $0.evidence.first?.timestamp) }
        record.takeaways.forEach { append("action:\($0.id)", .action, $0.text, $0.evidence.first?.timestamp) }
        record.review.openQuestions.forEach { append("question:\($0.id)", .question, $0.text, $0.evidence.first?.timestamp) }
        record.notes.forEach { append("note:\($0.id)", .note, $0.text, $0.timeOffset) }
        record.artifacts.forEach { append("artifact:\($0.id)", .artifact, "\($0.title): \($0.body)") }
        return result
    }
}
