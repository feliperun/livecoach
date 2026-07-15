import Foundation

/// Human-readable Markdown document for a `MemoryNote`. Frontmatter owns the
/// fields people commonly edit outside CueMe; structured session detail remains
/// in the adjacent JSON sidecar and is projected into readable sections.
enum NoteDocument {
    static let filename = "note.md"
    static let bodyStart = "<!-- cueme:body:start -->"
    static let bodyEnd = "<!-- cueme:body:end -->"

    static func frontmatter(for note: MemoryNote) -> [String] {
        [
            "---",
            "id: \(quoted(note.id.uuidString))",
            "title: \(quoted(note.title))",
            "kind: \(note.noteKind.rawValue)",
            "created_at: \(quoted(ISO8601DateFormatter().string(from: note.startedAt)))",
            "updated_at: \(quoted(ISO8601DateFormatter().string(from: note.modifiedAt)))",
            "project_id: \(note.projectID.map { quoted($0.uuidString) } ?? "null")",
            "labels: \(jsonArray(note.labels))",
            "title_source: \(note.titleSource.rawValue)",
            "has_recording: \(note.containsRecording ? "true" : "false")",
            "---"
        ]
    }

    static func userBodyLines(for note: MemoryNote) -> [String] {
        var lines = [bodyStart]
        let body = note.markdownBody.trimmingCharacters(in: .newlines)
        if !body.isEmpty { lines.append(contentsOf: body.components(separatedBy: .newlines)) }
        lines.append(bodyEnd)
        return lines
    }

    static func mergeCanonicalFields(from url: URL, into value: MemoryNote) -> MemoryNote {
        guard let markdown = try? String(contentsOf: url, encoding: .utf8),
              let parsed = parse(markdown) else { return value }
        var note = value
        if let title = parsed.values["title"], !title.isEmpty {
            note.displayTitle = title
        }
        if let kind = parsed.values["kind"].flatMap(MemoryNoteKind.init(rawValue:)) {
            note.noteKind = kind
        }
        if let source = parsed.values["title_source"].flatMap(NoteTitleSource.init(rawValue:)) {
            note.titleSource = source
        }
        if let project = parsed.values["project_id"], project != "null" {
            note.projectID = UUID(uuidString: project)
        } else if parsed.values.keys.contains("project_id") {
            note.projectID = nil
        }
        note.labels = parsed.labels
        note.markdownBody = parsed.body
        if let updated = parsed.values["updated_at"].flatMap(ISO8601DateFormatter().date(from:)) {
            note.modifiedAt = updated
        }
        return note
    }

    private struct Parsed {
        var values: [String: String]
        var labels: [String]
        var body: String
    }

    private static func parse(_ markdown: String) -> Parsed? {
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first == "---",
              let close = lines.dropFirst().firstIndex(of: "---") else { return nil }
        var values: [String: String] = [:]
        for line in lines[1..<close] {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            values[key] = unquoted(value)
        }
        let labels = decodeArray(values["labels"] ?? "[]")
        let remainder = Array(lines[lines.index(after: close)...])
        let body: String
        if let start = remainder.firstIndex(of: bodyStart),
           let end = remainder[(start + 1)...].firstIndex(of: bodyEnd) {
            body = remainder[(start + 1)..<end].joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
        } else {
            body = ""
        }
        return Parsed(values: values, labels: labels, body: body)
    }

    private static func quoted(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return encoded
    }

    private static func unquoted(_ value: String) -> String {
        guard value.hasPrefix("\""),
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else { return value }
        return decoded
    }

    private static func jsonArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let encoded = String(data: data, encoding: .utf8) else { return "[]" }
        return encoded
    }

    private static func decodeArray(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return decoded
    }
}
