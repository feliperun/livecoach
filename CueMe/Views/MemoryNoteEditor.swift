import SwiftUI
import UniformTypeIdentifiers

struct MemoryNoteEditor: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    @State private var draft: String
    @State private var preview = false
    @State private var importingAttachment = false

    init(record: SessionRecord) {
        self.record = record
        _draft = State(initialValue: record.markdownBody)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Theme.divider).frame(height: 1)
            if preview {
                MarkdownReadingView(markdown: draft)
            } else {
                TextEditor(text: $draft)
                    .font(.system(size: 16.5, weight: .regular, design: .serif))
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 42)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 920, maxHeight: .infinity)
                    .background(Theme.canvas)
                    .accessibilityIdentifier("note.editor")
                    .task(id: draft) {
                        guard draft != record.markdownBody else { return }
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        app.updateMarkdownBody(record.id, body: draft)
                    }
            }
        }
        .background(Theme.canvas)
        .onChange(of: record.markdownBody) { _, value in
            if value != draft { draft = value }
        }
        .fileImporter(
            isPresented: $importingAttachment,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            try? app.addAttachment(from: url, to: record.id)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Label(
                preview ? "Leitura" : "Markdown",
                systemImage: preview ? "book.pages" : "text.cursor"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            Spacer()
            if !record.attachments.isEmpty {
                Label("\(record.attachments.count)", systemImage: "paperclip")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Button { importingAttachment = true } label: {
                Label("Anexar", systemImage: "paperclip")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                if !preview, draft != record.markdownBody {
                    app.updateMarkdownBody(record.id, body: draft)
                }
                preview.toggle()
            } label: {
                Label(preview ? "Editar" : "Ler", systemImage: preview ? "pencil" : "book.open")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("note.editor.preview")
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Theme.panel)
    }
}

private struct MarkdownReadingView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 15) {
                if blocks.isEmpty {
                    ContentUnavailableView(
                        "Uma página em branco",
                        systemImage: "text.book.closed",
                        description: Text("Escreva para transformar o que você vive em memória disponível.")
                    )
                } else {
                    ForEach(blocks) { block in
                        blockView(block)
                    }
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 58)
            .padding(.vertical, 44)
        }
        .background(Theme.canvas)
        .accessibilityIdentifier("note.editor.reading")
        .accessibilityValue(accessibleText)
    }

    private var blocks: [MarkdownReadingBlock] { MarkdownReadingBlock.parse(markdown) }
    private var accessibleText: String { blocks.map(\.text).joined(separator: "\n") }

    @ViewBuilder
    private func blockView(_ block: MarkdownReadingBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(block.text)
                .font(.system(size: level == 1 ? 31 : (level == 2 ? 25 : 20), weight: .bold, design: .rounded))
                .padding(.top, level == 1 ? 4 : 12)
                .textSelection(.enabled)
        case .quote:
            Text(block.text)
                .font(.system(size: 17, weight: .medium, design: .serif))
                .italic().lineSpacing(5)
                .padding(.leading, 16).padding(.vertical, 5)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.violet).frame(width: 3) }
                .textSelection(.enabled)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Circle().fill(Theme.violet).frame(width: 5, height: 5)
                Text(block.text).font(.system(size: 17, design: .serif)).lineSpacing(5)
            }
            .textSelection(.enabled)
        case .code:
            Text(block.text)
                .font(.system(size: 14, design: .monospaced))
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
                .textSelection(.enabled)
        case .paragraph:
            Text(block.text)
                .font(.system(size: 17.5, weight: .regular, design: .serif))
                .lineSpacing(6)
                .textSelection(.enabled)
        }
    }
}

private struct MarkdownReadingBlock: Identifiable {
    enum Kind { case heading(Int), paragraph, quote, bullet, code }
    let id = UUID()
    let kind: Kind
    let text: String

    static func parse(_ markdown: String) -> [Self] {
        var result: [Self] = []
        var paragraph: [String] = []
        var code: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(.init(kind: .paragraph, text: paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }
        func flushCode() {
            guard !code.isEmpty else { return }
            result.append(.init(kind: .code, text: code.joined(separator: "\n")))
            code.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode { flushCode() } else { flushParagraph() }
                inCode.toggle()
            } else if inCode {
                code.append(rawLine)
            } else if line.isEmpty {
                flushParagraph()
            } else if let heading = heading(line) {
                flushParagraph()
                result.append(.init(kind: .heading(heading.level), text: heading.text))
            } else if line.hasPrefix("> ") {
                flushParagraph()
                result.append(.init(kind: .quote, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                result.append(.init(kind: .bullet, text: String(line.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        flushCode()
        return result
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), line.dropFirst(count).first == " " else { return nil }
        return (count, String(line.dropFirst(count + 1)))
    }
}
