import SwiftUI

/// Layout compacto-first: feito pra viver numa janela pequena ao lado do Zoom/Meet.
/// Hierarquia: pergunta atual no topo → dica do coach (herói) → painéis colapsáveis.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            HeaderBar()
            Divider()

            QuestionBanner()

            CoachingPane()
                .frame(maxHeight: .infinity)

            Divider()
            CollapsiblePanels()
            InputBar()
        }
        .background(.background)
        .sheet(isPresented: $app.showSettings) {
            BriefEditor()
        }
    }
}

/// Transcrição e resumo ficam fora do caminho — colapsáveis, finos.
private struct CollapsiblePanels: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            DisclosureGroup(isExpanded: $app.showTranscript) {
                TranscriptPane()
                    .frame(height: 230)
            } label: {
                Label("Transcrição", systemImage: "waveform")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            DisclosureGroup(isExpanded: $app.showSummary) {
                SummaryPane()
                    .frame(height: 140)
            } label: {
                HStack(spacing: 6) {
                    Label("Resumo", systemImage: "list.bullet.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                    if !app.summaryBullets.isEmpty {
                        Text("\(app.summaryBullets.count)")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()
        }
    }
}

/// Pergunta/deixa mais recente do interlocutor — fixa no topo, com tradução destacada.
struct QuestionBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let q = app.currentQuestion {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("❓ ELE DISSE")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.purple)
                    Spacer()
                }
                Text(q.text)
                    .font(.system(size: 16, weight: .semibold))
                    .lineSpacing(1)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if app.brief.isForeign, let t = q.translation, !t.isEmpty {
                    Text(t.markdownAttributed)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.purple.opacity(0.09))
        }
    }
}

#Preview {
    RootView().environment(AppModel())
}
