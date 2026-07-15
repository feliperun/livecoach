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
}
