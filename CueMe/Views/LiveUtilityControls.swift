import SwiftUI

struct LiveNoteButton: View {
    @Environment(AppModel.self) private var app
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "note.text.badge.plus")
                if !app.sessionNotes.isEmpty { Text("\(app.sessionNotes.count)") }
            }
            .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.amber)
            .frame(minWidth: 27, minHeight: 24)
        }
        .buttonStyle(.plain).help("Anotar agora")
        .accessibilityIdentifier("live.note")
        .popover(isPresented: $showing) { LiveNotesPopover() }
    }
}

private struct LiveNotesPopover: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                TextField("Anotação neste momento…", text: $app.noteDraft)
                    .accessibilityIdentifier("live.note.input")
                    .textFieldStyle(.plain).font(.system(size: 11.5)).onSubmit(app.addLiveNote)
                Button(action: app.addLiveNote) { Image(systemName: "arrow.up.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.violet)
                    .accessibilityIdentifier("live.note.submit")
            }
            .padding(9).background(Theme.interactive, in: RoundedRectangle(cornerRadius: 9))
            ScrollView {
                LazyVStack(spacing: 7) {
                    if app.sessionNotes.isEmpty { ReviewEmptyRow(text: "Sem anotações") }
                    ForEach(app.sessionNotes.sorted { $0.timeOffset < $1.timeOffset }) { note in
                        LiveNoteEditor(note: note)
                    }
                }
            }
        }
        .padding(12).frame(width: 350, height: 290)
    }
}

private struct LiveNoteEditor: View {
    @Environment(AppModel.self) private var app
    let note: SessionNote
    @State private var draft = ""

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text(SessionArchive.clock(note.timeOffset))
                .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Theme.amber)
            TextField("Nota", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 11.5))
                .onSubmit { app.updateLiveNote(note.id, text: draft) }
            Button { app.updateLiveNote(note.id, text: draft) } label: { Image(systemName: "checkmark") }
            Button(role: .destructive) { app.deleteLiveNote(note.id) } label: { Image(systemName: "trash") }
        }
        .buttonStyle(.plain)
        .padding(8).background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
        .onAppear { draft = note.text }
        .onChange(of: note.text) { _, value in draft = value }
    }
}

struct LiveDetailsButton: View {
    @Environment(AppModel.self) private var app
    @State private var showing = false
    @State private var tab = 0

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 27, height: 24)
        }
        .buttonStyle(.plain).help("Transcrição, ata e pergunta manual")
        .popover(isPresented: $showing) {
            VStack(spacing: 8) {
                Picker("Detalhes", selection: $tab) {
                    Text("Transcrição").tag(0)
                    Text("Ata").tag(1)
                }
                .pickerStyle(.segmented)
                Group {
                    if tab == 0 { TranscriptPane() } else { SummaryPane() }
                }
                .frame(height: 280)
                if !app.brief.mode.isPassive { manualCoach }
            }
            .padding(10).frame(width: 460)
        }
    }

    private var manualCoach: some View {
        @Bindable var app = app
        return HStack(spacing: 7) {
            TextField("Perguntar ao Coach…", text: $app.manualInput)
                .textFieldStyle(.plain).font(.system(size: 11.5)).onSubmit(app.ask)
            Button(action: app.ask) { Image(systemName: "arrow.up.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(Theme.violet)
        }
        .padding(9).background(Theme.interactive, in: RoundedRectangle(cornerRadius: 9))
    }
}
