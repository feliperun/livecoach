import SwiftUI

struct SessionCoachPane: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                HStack {
                    Text("Modelo").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Coach", selection: Binding(
                        get: { app.coachModel },
                        set: { app.coachModel = $0 }
                    )) {
                        ForEach(CoachModel.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small)
                }
                if record.coachCards.isEmpty { emptyState }
                ForEach(record.coachCards.reversed()) { card in MemoryCoachCard(card: card) }
            }
            .padding(14)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .light)).foregroundStyle(Theme.violet.opacity(0.7))
            Text("Sem dicas nesta sessão").font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
    }
}
