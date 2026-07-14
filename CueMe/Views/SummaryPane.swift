import SwiftUI

/// Resumo rolante compacto (vive colapsado).
struct SummaryPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                if app.summaryBullets.isEmpty {
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
                    ForEach(Array(app.summaryBullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .top, spacing: 5) {
                            Text("•").foregroundStyle(.secondary)
                            Text(bullet).textSelection(.enabled)
                        }
                        .font(.system(size: 13))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
}
