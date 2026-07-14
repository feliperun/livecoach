import SwiftUI

struct LiveTransportBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        HStack(spacing: 9) {
            Image(systemName: app.isSessionBusy ? "record.circle.fill" : "record.circle")
                .foregroundStyle(app.isSessionBusy ? Theme.rose : .secondary)
            if let start = app.sessionStartTime {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(SessionArchive.clock(context.date.timeIntervalSince(start)))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                }
            } else {
                Text("Pronto para gravar")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 18)

            Image(systemName: "note.text.badge.plus")
                .font(.system(size: 10)).foregroundStyle(Theme.amber)
            TextField("Anotação neste momento…", text: $app.noteDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .onSubmit(app.addLiveNote)
                .disabled(app.sessionStartTime == nil)
            Button(action: app.addLiveNote) {
                Image(systemName: "arrow.up.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.brand)
            .disabled(app.noteDraft.trimmingCharacters(in: .whitespaces).isEmpty || app.sessionStartTime == nil)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.surface.opacity(0.92))
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }
}
