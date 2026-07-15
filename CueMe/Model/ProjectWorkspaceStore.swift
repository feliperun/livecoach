import Foundation

enum ProjectWorkspaceStore {
    static func directory(for project: KnowledgeProject) -> URL {
        SessionStore.rootURL.appendingPathComponent(project.storageFolderName, isDirectory: true)
    }

    @discardableResult
    static func save(_ project: KnowledgeProject) -> URL? {
        let directory = directory(for: project)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let markdown = [
                "---",
                "id: \"\(project.id.uuidString)\"",
                "name: \"\(escaped(project.name))\"",
                "created_at: \"\(ISO8601DateFormatter().string(from: project.createdAt))\"",
                "archived: \(project.archived ? "true" : "false")",
                "---",
                "",
                "# \(project.name)",
                "",
                project.summary
            ].joined(separator: "\n") + "\n"
            try markdown.write(
                to: directory.appendingPathComponent("project.md"),
                atomically: true,
                encoding: .utf8
            )
            return directory
        } catch {
            return nil
        }
    }

    static func relativeDirectory(for project: KnowledgeProject?) -> String {
        project?.storageFolderName ?? "_Inbox"
    }

    /// Discovers Project folders from the workspace. `project.md` wins over the
    /// legacy App Support catalog; the latter is used only to bootstrap folders
    /// during the 1.0 migration.
    static func loadAll(merging legacy: [KnowledgeProject] = []) -> [KnowledgeProject] {
        var projects = Dictionary(uniqueKeysWithValues: discoveredProjects().map { ($0.id, $0) })
        for project in legacy where projects[project.id] == nil {
            _ = save(project)
            var migrated = project
            migrated.folderName = project.storageFolderName
            projects[project.id] = migrated
        }
        return projects.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func slug(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let slug = parts.joined(separator: "-").lowercased()
        return String((slug.isEmpty ? "project" : slug).prefix(54))
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func discoveredProjects() -> [KnowledgeProject] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: SessionStore.rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return directories.compactMap { directory in
            guard directory.lastPathComponent != "_Inbox",
                  (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return parse(directory.appendingPathComponent("project.md"), folderName: directory.lastPathComponent)
        }
    }

    private static func parse(_ url: URL, folderName: String) -> KnowledgeProject? {
        guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first == "---",
              let close = lines.dropFirst().firstIndex(of: "---") else { return nil }
        var values: [String: String] = [:]
        for line in lines[1..<close] {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let raw = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            values[key] = unquoted(raw)
        }
        guard let id = values["id"].flatMap(UUID.init(uuidString:)),
              let name = values["name"], !name.isEmpty else { return nil }
        let createdAt = values["created_at"].flatMap(ISO8601DateFormatter().date(from:)) ?? Date()
        let body = lines[lines.index(after: close)...]
            .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty || $0.hasPrefix("# ") })
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return KnowledgeProject(
            id: id,
            name: name,
            summary: body,
            createdAt: createdAt,
            archived: values["archived"] == "true",
            folderName: folderName
        )
    }

    private static func unquoted(_ value: String) -> String {
        guard value.hasPrefix("\""),
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else { return value }
        return decoded
    }
}
