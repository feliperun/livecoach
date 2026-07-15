import Foundation

enum RelevantMemoryContextBuilder {
    static func build(
        for brief: SessionBrief,
        records: [SessionRecord],
        index: SemanticMemoryIndex = .shared
    ) -> String? {
        let query = [brief.goal, brief.details, brief.keyterms.joined(separator: " ")]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !query.isEmpty else { return nil }
        let rankedIDs = index.search(
            query: query,
            date: .all,
            type: .all,
            records: records
        ).map(\.recordID)
        return format(records: records, rankedIDs: rankedIDs)
    }

    static func format(
        records: [SessionRecord],
        rankedIDs: [UUID],
        characterLimit: Int = 12_000
    ) -> String? {
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var output = ""
        for id in rankedIDs.prefix(5) {
            guard let record = byID[id] else { continue }
            let content = noteContent(record)
            guard !content.isEmpty else { continue }
            let labels = record.labels.isEmpty ? "" : " · #\(record.labels.joined(separator: " #"))"
            let section = """
            ### \(record.title)
            \(record.noteKind.label) · \(record.startedAt.formatted(date: .abbreviated, time: .omitted))\(labels)
            \(String(content.prefix(2_200)))

            """
            guard output.count + section.count <= characterLimit else { break }
            output += section
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func noteContent(_ record: SessionRecord) -> String {
        var sections: [String] = []
        if !record.markdownBody.isEmpty { sections.append(record.markdownBody) }
        if !record.minutes.overview.isEmpty { sections.append(record.minutes.overview) }
        if !record.review.decisions.isEmpty {
            sections.append("Decisões: " + record.review.decisions.map(\.text).joined(separator: "; "))
        }
        if !record.takeaways.isEmpty {
            sections.append("Ações: " + record.takeaways.map(\.text).joined(separator: "; "))
        }
        if sections.isEmpty {
            sections.append(record.transcript.filter(\.isFinal).prefix(8).map(\.text).joined(separator: " "))
        }
        return sections.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
