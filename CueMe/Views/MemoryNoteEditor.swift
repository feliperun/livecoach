import SwiftUI
import UniformTypeIdentifiers

struct MemoryNoteEditor: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord

    @State private var document: MarkdownBlockDocument
    @State private var rawDraft: String
    @State private var sourceMode = false
    @State private var importingAttachment = false
    @State private var focusedBlockID: UUID?
    @State private var formatRequest: MarkdownBlockFormatRequest?

    init(record: SessionRecord) {
        self.record = record
        _document = State(initialValue: MarkdownBlockDocument(markdown: record.markdownBody))
        _rawDraft = State(initialValue: record.markdownBody)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Theme.divider).frame(height: 1)
            if sourceMode {
                sourceEditor
            } else {
                MarkdownBlockEditor(
                    document: $document,
                    focusedBlockID: $focusedBlockID,
                    formatRequest: formatRequest
                )
            }
        }
        .background(Theme.canvas)
        .task(id: document.markdown) {
            guard !sourceMode else { return }
            await persist(document.markdown)
        }
        .task(id: rawDraft) {
            guard sourceMode else { return }
            await persist(rawDraft)
        }
        .onChange(of: record.markdownBody) { _, value in
            let current = sourceMode ? rawDraft : document.markdown
            guard value != current else { return }
            rawDraft = value
            document = MarkdownBlockDocument(markdown: value)
        }
        .onDisappear {
            let latest = sourceMode ? rawDraft : document.markdown
            if latest != record.markdownBody { app.updateMarkdownBody(record.id, body: latest) }
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
        HStack(spacing: 7) {
            Label(
                sourceMode ? "Markdown fonte" : "Editor em blocos",
                systemImage: sourceMode ? "chevron.left.forwardslash.chevron.right" : "square.stack.3d.up"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)

            if !sourceMode {
                formattingDivider
                formatButton("B", style: .bold, help: "Negrito (⌘B)")
                    .fontWeight(.bold)
                formatButton("I", style: .italic, help: "Itálico (⌘I)")
                    .italic()
                formatButton("S", style: .strikethrough, help: "Tachado (⌘⇧X)")
                    .strikethrough()
                formatButton("</>", style: .code, help: "Código inline (⌘⇧C)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            }

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

            Button { toggleSourceMode() } label: {
                Label(
                    sourceMode ? "Blocos" : "Fonte",
                    systemImage: sourceMode ? "square.stack.3d.up" : "chevron.left.forwardslash.chevron.right"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("note.editor.source")
            .help(sourceMode ? "Voltar ao editor visual" : "Editar o Markdown gerado")
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
        .background(Theme.panel)
    }

    private var formattingDivider: some View {
        Rectangle().fill(Theme.divider).frame(width: 1, height: 20).padding(.horizontal, 3)
    }

    private func formatButton<Content: View>(
        _ title: String,
        style: MarkdownInlineStyle,
        help: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            guard let focusedBlockID else { return }
            formatRequest = .init(blockID: focusedBlockID, style: style)
        } label: {
            content()
                .frame(width: 25, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.interactive, in: RoundedRectangle(cornerRadius: 6))
        .disabled(focusedBlockID == nil)
        .help(help)
        .accessibilityIdentifier("note.editor.format.\(String(describing: style))")
    }

    private func formatButton(
        _ title: String,
        style: MarkdownInlineStyle,
        help: String
    ) -> some View {
        formatButton(title, style: style, help: help) { Text(title) }
    }

    private var sourceEditor: some View {
        TextEditor(text: $rawDraft)
            .font(.system(size: 14.5, weight: .regular, design: .monospaced))
            .lineSpacing(4)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 48)
            .padding(.vertical, 34)
            .frame(maxWidth: 920, maxHeight: .infinity)
            .background(Theme.canvas)
            .accessibilityIdentifier("note.editor.raw")
    }

    private func toggleSourceMode() {
        if sourceMode {
            document = MarkdownBlockDocument(markdown: rawDraft)
            sourceMode = false
        } else {
            rawDraft = document.markdown
            sourceMode = true
        }
        focusedBlockID = nil
    }

    private func persist(_ value: String) async {
        guard value != record.markdownBody else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        app.updateMarkdownBody(record.id, body: value)
    }
}
