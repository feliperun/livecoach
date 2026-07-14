import SwiftUI

/// Resumo rolante compacto (vive colapsado).
struct SummaryPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("ATA")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.cyan)
                    Spacer()
                    Picker("Ata", selection: Binding(
                        get: { app.summaryModel },
                        set: { app.summaryModel = $0 }
                    )) {
                        ForEach(CoachModel.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.mini)
                }
                if app.minutes.isEmpty {
                    if let error = app.summaryBackendError {
                        Label("Resumo offline", systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.rose)
                            .help(error)
                    } else {
                        Text("Anotando…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !app.minutes.overview.isEmpty {
                        Text(app.minutes.overview)
                            .font(.system(size: 12.5, weight: .medium))
                            .textSelection(.enabled)
                    }
                    ForEach(app.minutes.topics) { topic in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topic.title)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(Theme.violet)
                            Text(topic.summary)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
}
