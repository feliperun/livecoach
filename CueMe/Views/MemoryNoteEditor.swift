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
                // Empty-note affordances sit *below* the editor so the first
                // block stays at the top and immediately focusable.
                if isBlank {
                    BlankNoteState(record: record).frame(maxHeight: 260)
                }
            }
        }
        .background(Theme.paper)
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

    /// A brand-new written note with nothing typed yet.
    private var isBlank: Bool {
        record.origin == .written
            && record.transcript.isEmpty
            && document.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && rawDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            .background(Theme.paper)
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

/// Empty-note surface: record / import / playbook affordances so a fresh note
/// is never a dead end. Absorbs the launch affordances into the note itself.
private struct BlankNoteState: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    @State private var playbook: Mode = .meeting

    private let playbooks: [(String, Mode)] = [
        ("Sales", .sales),
        ("Interview", .interview),
        ("Difficult conversation", .difficult),
        ("Open meeting", .meeting),
        ("Recording only — no coach", .recording),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(record.startedAt.formatted(date: .abbreviated, time: .omitted).uppercased())
                .font(.ui(11, .semibold)).tracking(1.2).foregroundStyle(Theme.faint)

            Text("Comece a escrever — ou traga a reunião para esta nota:")
                .font(.read(17)).italic().foregroundStyle(Theme.faint)

            HStack(alignment: .top, spacing: 12) {
                recordCard
                VStack(spacing: 10) {
                    smallCard(title: "⤓ Importar áudio", detail: "Voice Memos, arquivo ou arraste — transcrito aqui") {
                        app.chooseAudioFiles()
                    }
                    .disabled(app.isSessionBusy || app.audioImportStatus?.isActive == true)
                }
                .frame(maxWidth: 240)
            }

            playbookSection
        }
        .frame(maxWidth: 720, alignment: .leading)
        .padding(.horizontal, 44).padding(.top, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordCard: some View {
        Button(action: startRecording) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    ZStack {
                        Circle().fill(Theme.amber).frame(width: 30, height: 30)
                        Circle().fill(.white).frame(width: 10, height: 10)
                    }
                    Text("Gravar esta reunião").font(.ui(15, .bold)).foregroundStyle(Theme.amberText)
                    Spacer(minLength: 6)
                    Text("⌘R").font(.ui(10)).foregroundStyle(Theme.amberText)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                }
                Text("Mic + áudio do sistema, os dois lados transcritos. Gravação, transcrição e ata viram blocos desta nota.")
                    .font(.ui(12.5)).foregroundStyle(Theme.amberText).opacity(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.amberSoft, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.amber.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: .command)
        .accessibilityIdentifier("note.blank.record")
    }

    private func smallCard(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ui(13, .semibold)).foregroundStyle(Theme.ink)
                Text(detail).font(.ui(11.5)).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 15).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.line))
        }
        .buttonStyle(.plain)
    }

    private var playbookSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("SE VOCÊ GRAVAR — PLAYBOOK DO COACH")
                .font(.ui(10, .semibold)).tracking(1.2).foregroundStyle(Theme.faint)
            FlowPills(items: playbooks.map(\.0), selectedIndex: playbooks.firstIndex { $0.1 == playbook }) { idx in
                playbook = playbooks[idx].1
            }
            Text("Anexe um briefing ou docs de contexto no preflight · STT on-device por padrão")
                .font(.ui(11.5)).foregroundStyle(Theme.faint)
        }
    }

    private func startRecording() {
        app.brief.mode = playbook
        app.showLiveSession()
        app.start()
    }
}

/// Simple wrapping pill row with single selection.
private struct FlowPills: View {
    let items: [String]
    let selectedIndex: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, title in
                    let selected = index == selectedIndex
                    Button { onSelect(index) } label: {
                        HStack(spacing: 5) {
                            Text(title).font(.ui(12, selected ? .semibold : .regular)).fixedSize()
                            if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                        }
                        .foregroundStyle(selected ? Theme.violetDeep : Theme.ink2)
                        .padding(.horizontal, 13).padding(.vertical, 5)
                        .background(selected ? Theme.violetSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.violet.opacity(0.35) : Theme.line))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
