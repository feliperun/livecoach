import Foundation

enum MarkdownBlockKind: String, CaseIterable, Sendable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case quote
    case bullet
    case numbered
    case checklistUnchecked
    case checklistChecked
    case code
    case divider

    var isList: Bool {
        switch self {
        case .bullet, .numbered, .checklistUnchecked, .checklistChecked: true
        default: false
        }
    }
}

struct MarkdownBlock: Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: MarkdownBlockKind
    var content: String
    var language: String?

    init(
        id: UUID = UUID(),
        kind: MarkdownBlockKind = .paragraph,
        content: String = "",
        language: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.language = language
    }
}

/// An editor-friendly projection of a Markdown body. Blocks are ephemeral UI
/// state; `markdown` is the only value persisted in the user's `note.md`.
struct MarkdownBlockDocument: Equatable, Sendable {
    var blocks: [MarkdownBlock]

    init(markdown: String) {
        blocks = Self.parse(markdown)
        if blocks.isEmpty { blocks = [.init()] }
    }

    init(blocks: [MarkdownBlock]) {
        self.blocks = blocks.isEmpty ? [.init()] : blocks
    }

    var markdown: String {
        var result = ""
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                result += blocks[index - 1].kind.isList && block.kind.isList ? "\n" : "\n\n"
            }
            result += Self.serialize(block)
        }
        return result.trimmingCharacters(in: .newlines)
    }

    @discardableResult
    mutating func split(_ id: UUID, before: String, after: String) -> UUID {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return id }
        blocks[index].content = before
        let nextKind = Self.kindAfterReturn(from: blocks[index].kind)
        let next = MarkdownBlock(kind: nextKind, content: after)
        blocks.insert(next, at: index + 1)
        return next.id
    }

    mutating func insert(_ block: MarkdownBlock = .init(), after id: UUID?) {
        guard let id, let index = blocks.firstIndex(where: { $0.id == id }) else {
            blocks.append(block)
            return
        }
        blocks.insert(block, at: index + 1)
    }

    mutating func transform(_ id: UUID, to kind: MarkdownBlockKind) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[index].kind = kind
        if kind != .code { blocks[index].language = nil }
        if kind == .divider { blocks[index].content = "" }
    }

    mutating func update(_ id: UUID, content: String) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[index].content = content
    }

    mutating func toggleChecklist(_ id: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        switch blocks[index].kind {
        case .checklistUnchecked: blocks[index].kind = .checklistChecked
        case .checklistChecked: blocks[index].kind = .checklistUnchecked
        default: break
        }
    }

    @discardableResult
    mutating func mergeIntoPrevious(_ id: UUID) -> UUID? {
        guard let index = blocks.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        let previousID = blocks[index - 1].id
        blocks[index - 1].content += blocks[index].content
        blocks.remove(at: index)
        return previousID
    }

    mutating func remove(_ id: UUID) {
        blocks.removeAll { $0.id == id }
        if blocks.isEmpty { blocks = [.init()] }
    }

    mutating func move(_ id: UUID, before destinationID: UUID) {
        guard id != destinationID,
              let source = blocks.firstIndex(where: { $0.id == id }),
              let destination = blocks.firstIndex(where: { $0.id == destinationID }) else { return }
        let block = blocks.remove(at: source)
        let adjustedDestination = source < destination ? destination - 1 : destination
        blocks.insert(block, at: adjustedDestination)
    }

    private static func parse(_ markdown: String) -> [MarkdownBlock] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var result: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            if let fence = codeFence(line) {
                var code: [String] = []
                index += 1
                while index < lines.count, !isClosingFence(lines[index], marker: fence.marker) {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                result.append(.init(kind: .code, content: code.joined(separator: "\n"), language: fence.language))
                continue
            }

            if isDivider(line) {
                result.append(.init(kind: .divider))
                index += 1
                continue
            }

            if let heading = heading(line) {
                result.append(.init(kind: heading.kind, content: heading.content))
                index += 1
                continue
            }

            if let checklist = checklist(line) {
                result.append(.init(kind: checklist.checked ? .checklistChecked : .checklistUnchecked, content: checklist.content))
                index += 1
                continue
            }

            if let content = prefixedContent(line, prefixes: ["> ", ">"] ) {
                result.append(.init(kind: .quote, content: content))
                index += 1
                continue
            }

            if let content = prefixedContent(line, prefixes: ["- ", "* ", "+ "]) {
                result.append(.init(kind: .bullet, content: content))
                index += 1
                continue
            }

            if let content = numberedContent(line) {
                result.append(.init(kind: .numbered, content: content))
                index += 1
                continue
            }

            var paragraph = [line]
            index += 1
            while index < lines.count,
                  !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                  !isStructuralStart(lines[index]) {
                paragraph.append(lines[index])
                index += 1
            }
            result.append(.init(kind: .paragraph, content: paragraph.joined(separator: "\n")))
        }
        return result
    }

    private static func serialize(_ block: MarkdownBlock) -> String {
        switch block.kind {
        case .paragraph: block.content
        case .heading1: "# \(block.content)"
        case .heading2: "## \(block.content)"
        case .heading3: "### \(block.content)"
        case .quote: block.content.components(separatedBy: .newlines).map { "> \($0)" }.joined(separator: "\n")
        case .bullet: "- \(block.content)"
        case .numbered: "1. \(block.content)"
        case .checklistUnchecked: "- [ ] \(block.content)"
        case .checklistChecked: "- [x] \(block.content)"
        case .code:
            "```\(block.language ?? "")\n\(block.content)\n```"
        case .divider: "---"
        }
    }

    private static func kindAfterReturn(from kind: MarkdownBlockKind) -> MarkdownBlockKind {
        switch kind {
        case .bullet, .numbered, .checklistUnchecked: kind
        case .checklistChecked: .checklistUnchecked
        case .code: .code
        default: .paragraph
        }
    }

    private static func heading(_ line: String) -> (kind: MarkdownBlockKind, content: String)? {
        if line.hasPrefix("### ") { return (.heading3, String(line.dropFirst(4))) }
        if line.hasPrefix("## ") { return (.heading2, String(line.dropFirst(3))) }
        if line.hasPrefix("# ") { return (.heading1, String(line.dropFirst(2))) }
        return nil
    }

    private static func checklist(_ line: String) -> (checked: Bool, content: String)? {
        let lower = line.lowercased()
        if lower.hasPrefix("- [x] ") { return (true, String(line.dropFirst(6))) }
        if lower.hasPrefix("- [ ] ") { return (false, String(line.dropFirst(6))) }
        return nil
    }

    private static func numberedContent(_ line: String) -> String? {
        guard let match = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) else { return nil }
        return String(line[match.upperBound...])
    }

    private static func prefixedContent(_ line: String, prefixes: [String]) -> String? {
        guard let prefix = prefixes.first(where: line.hasPrefix) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    private static func codeFence(_ line: String) -> (marker: String, language: String?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") else { return nil }
        let marker = String(trimmed.prefix(3))
        let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return (marker, language.isEmpty ? nil : language)
    }

    private static func isClosingFence(_ line: String, marker: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(marker)
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        return compact == "---" || compact == "***" || compact == "___"
    }

    private static func isStructuralStart(_ line: String) -> Bool {
        codeFence(line) != nil || isDivider(line) || heading(line) != nil || checklist(line) != nil
            || prefixedContent(line, prefixes: ["> ", ">", "- ", "* ", "+ "]) != nil
            || numberedContent(line) != nil
    }
}
