import SwiftUI

struct SessionSummaryPane: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Ata", selection: Binding(
                        get: { app.summaryModel },
                        set: { app.summaryModel = $0 }
                    )) {
                        ForEach(CoachModel.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small)
                    Spacer()
                    generationButton
                }
                if record.minutes.isEmpty { emptyState }
                if !record.minutes.overview.isEmpty {
                    Text(record.minutes.overview)
                        .font(.system(size: 13, weight: .medium)).textSelection(.enabled)
                }
                ForEach(record.minutes.topics) { topic in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(topic.title).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.violet)
                        Text(topic.summary).font(.system(size: 12.5)).textSelection(.enabled)
                    }
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
                }
                if let error = app.postProcessingError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.rose)
                }
            }
            .padding(14)
        }
    }

    private var generationButton: some View {
        Button { Task { await app.generateSummary(for: record.id) } } label: {
            Label(
                app.postProcessingSessionID == record.id ? "Gerando…" : "Atualizar",
                systemImage: app.postProcessingSessionID == record.id ? "hourglass" : "arrow.clockwise"
            )
            .font(.system(size: 10.5, weight: .semibold))
        }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(app.postProcessingSessionID != nil)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 20, weight: .light)).foregroundStyle(Theme.violet.opacity(0.7))
            Text("Ata ainda não gerada").font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
    }
}
