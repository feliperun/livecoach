import SwiftUI

struct LiveTransportBar: View {
    @Environment(AppModel.self) private var app
    @State private var showNotes = false

    var body: some View {
        @Bindable var app = app

        HStack(spacing: 10) {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.rose)
                .symbolEffect(.pulse, options: .repeating, isActive: app.isSessionBusy)
            if let start = app.sessionStartTime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(SessionArchive.clock(context.date.timeIntervalSince(start)))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .contentTransition(.numericText())
                }
            }

            Rectangle().fill(Theme.divider).frame(width: 1, height: 22)

            Button {
                showNotes.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                    if !app.sessionNotes.isEmpty { Text("\(app.sessionNotes.count)") }
                }
                .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.amber)
            .help("Ver e editar anotações")
            .popover(isPresented: $showNotes) {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        if app.sessionNotes.isEmpty {
                            Text("Sem anotações")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        ForEach(app.sessionNotes.sorted { $0.timeOffset < $1.timeOffset }) { note in
                            LiveNoteEditor(note: note)
                        }
                    }
                    .padding(12)
                }
                .frame(width: 340, height: 260)
            }

            HStack(spacing: 8) {
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 11)).foregroundStyle(Theme.amber)
                TextField("Anotação neste momento…", text: $app.noteDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .onSubmit(app.addLiveNote)
                Button(action: app.addLiveNote) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.violet)
                .disabled(app.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Theme.interactive, in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(10)
        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.divider))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

private struct LiveNoteEditor: View {
    @Environment(AppModel.self) private var app
    let note: SessionNote
    @State private var draft = ""

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text(SessionArchive.clock(note.timeOffset))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.amber)
            TextField("Nota", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .onSubmit { app.updateLiveNote(note.id, text: draft) }
            Button { app.updateLiveNote(note.id, text: draft) } label: {
                Image(systemName: "checkmark")
            }
            Button(role: .destructive) { app.deleteLiveNote(note.id) } label: {
                Image(systemName: "trash")
            }
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
        .onAppear { draft = note.text }
        .onChange(of: note.text) { _, value in draft = value }
    }
}
