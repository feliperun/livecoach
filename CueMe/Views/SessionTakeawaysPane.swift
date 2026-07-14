import SwiftUI

struct SessionTakeawaysPane: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    @State private var takeawayText = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        generationButton
                    }
                    if record.takeaways.isEmpty { emptyState }
                    ForEach(record.takeaways) { item in
                        Button {
                            app.toggleTakeaway(sessionID: record.id, takeawayID: item.id)
                        } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isDone ? Theme.mint : .secondary)
                                Text(item.text)
                                    .strikethrough(item.isDone)
                                    .foregroundStyle(item.isDone ? .secondary : .primary)
                                Spacer()
                            }
                            .font(.system(size: 12.5)).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if let error = app.postProcessingError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(size: 10.5)).foregroundStyle(Theme.rose)
                    }
                }
                .padding(14)
            }
            composer
        }
    }

    private var generationButton: some View {
        Button { Task { await app.generateTakeaways(for: record.id) } } label: {
            Label(
                app.postProcessingSessionID == record.id ? "Gerando…" : "Extrair",
                systemImage: app.postProcessingSessionID == record.id ? "hourglass" : "wand.and.stars"
            )
            .font(.system(size: 10.5, weight: .semibold))
        }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(app.postProcessingSessionID != nil)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Adicionar pendência", text: $takeawayText)
                .textFieldStyle(.plain).font(.system(size: 12)).onSubmit(addTakeaway)
            Button(action: addTakeaway) { Image(systemName: "arrow.up.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(Theme.brand)
                .disabled(takeawayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 20, weight: .light)).foregroundStyle(Theme.violet.opacity(0.7))
            Text("Nada pendente ainda").font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
    }

    private func addTakeaway() {
        app.addTakeaway(to: record.id, text: takeawayText)
        takeawayText = ""
    }
}
