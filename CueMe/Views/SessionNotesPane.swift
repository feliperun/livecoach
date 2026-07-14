import SwiftUI

struct SessionNotesPane: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    let player: MeetingPlayer
    @State private var noteText = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 7) {
                    if record.notes.isEmpty {
                        emptyState
                    }
                    ForEach(record.notes.sorted { $0.timeOffset < $1.timeOffset }) { note in
                        EditableMemoryNote(sessionID: record.id, note: note) {
                            player.seek(to: note.timeOffset)
                        }
                    }
                }
                .padding(14)
            }
            composer
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Nota em \(SessionArchive.clock(player.currentTime))", text: $noteText)
                .textFieldStyle(.plain).font(.system(size: 12))
                .onSubmit(addNote)
            Button(action: addNote) { Image(systemName: "arrow.up.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(Theme.brand)
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Theme.violet.opacity(0.7))
            Text("Anote sem sair da timeline")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
    }

    private func addNote() {
        app.addNote(to: record.id, text: noteText, timeOffset: player.currentTime)
        noteText = ""
    }
}
