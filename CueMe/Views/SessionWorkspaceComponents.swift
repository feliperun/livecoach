import SwiftUI

enum SessionWorkspaceTab: String, CaseIterable, Identifiable {
    case coach, summary, transcript, notes, takeaways, generated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .coach: return "Coach"
        case .summary: return "Resumo"
        case .transcript: return "Transcrição"
        case .notes: return "Notas"
        case .takeaways: return "Ações"
        case .generated: return "Memória"
        }
    }

    var icon: String {
        switch self {
        case .coach: return "sparkles"
        case .summary: return "text.alignleft"
        case .transcript: return "waveform"
        case .notes: return "note.text"
        case .takeaways: return "checklist"
        case .generated: return "brain.head.profile"
        }
    }
}

struct SessionTabButton: View {
    let item: SessionWorkspaceTab
    let count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: item.icon)
                Text(item.label)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary.opacity(0.7))
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 7).padding(.vertical, 7)
            .background(selected ? Theme.violet.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(item.label)
    }
}

struct MemoryCoachCard: View {
    let card: CoachCard

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !card.guidePT.isEmpty {
                Text(card.guidePT)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.violet)
            }
            if let phrase = card.sayConversation ?? (card.sayNative.isEmpty ? nil : card.sayNative) {
                Text(phrase).font(.system(size: 14, weight: .semibold)).textSelection(.enabled)
            }
            if !card.keytermsConversation.isEmpty {
                Text(card.keytermsConversation.joined(separator: " · "))
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.divider))
    }
}

struct MemoryTranscriptLine: View {
    let line: TranscriptLine
    let speakerName: String
    let foreign: Bool
    let active: Bool
    let onTap: (() -> Void)?
    let onCorrect: (String) -> Void
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button(action: { onTap?() }) {
                Image(systemName: active ? "speaker.wave.2.fill" : "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(active ? Theme.violet : Color.white.opacity(0.2))
                    .frame(width: 12)
                    .opacity(onTap == nil ? 0 : 1)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(speakerName.uppercased())
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(line.speaker == .self ? Theme.cyan : Theme.violet)
                    if line.wasEdited {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 9)).foregroundStyle(Theme.amber)
                            .help("Original: \(line.originalText ?? "")")
                    }
                }
                if editing {
                    HStack {
                        TextField("Correção", text: $draft, axis: .vertical)
                            .textFieldStyle(.plain).font(.system(size: 12.5))
                            .onSubmit(save)
                        Button(action: save) { Image(systemName: "checkmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(Theme.mint)
                    }
                } else {
                    Text(line.text).font(.system(size: 12.5)).foregroundStyle(.primary).textSelection(.enabled)
                }
                    if foreign, let translation = line.translation, !translation.isEmpty {
                        Text(translation).font(.system(size: 11.5)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
            }
            Spacer()
            Button {
                draft = line.text
                editing.toggle()
            } label: { Image(systemName: editing ? "xmark" : "pencil") }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(active ? Theme.violet.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func save() {
        onCorrect(draft)
        editing = false
    }
}

struct EditableMemoryNote: View {
    @Environment(AppModel.self) private var app
    let sessionID: UUID
    let note: SessionNote
    let seek: () -> Void
    @State private var draft = ""

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button(action: seek) {
                Text(SessionArchive.clock(note.timeOffset))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.amber)
            }
            .buttonStyle(.plain)
            TextField("Nota", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12.5))
                .onSubmit { app.updateNote(sessionID: sessionID, noteID: note.id, text: draft) }
            Button { app.updateNote(sessionID: sessionID, noteID: note.id, text: draft) } label: {
                Image(systemName: "checkmark")
            }
            Button(role: .destructive) { app.deleteNote(sessionID: sessionID, noteID: note.id) } label: {
                Image(systemName: "trash")
            }
        }
        .buttonStyle(.plain)
        .padding(9).background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
        .onAppear { draft = note.text }
        .onChange(of: note.text) { _, value in draft = value }
    }
}
