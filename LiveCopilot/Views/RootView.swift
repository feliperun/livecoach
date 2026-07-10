import SwiftUI

/// Layout compacto-first: feito pra viver numa janela pequena ao lado do Zoom/Meet.
/// Hierarquia: pergunta atual no topo → dica do coach (herói) → painéis colapsáveis.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            HeaderBar()

            QuestionBanner()
                .padding(.horizontal, 12)
                .padding(.top, 10)

            CoachingPane()
                .frame(maxHeight: .infinity)

            CollapsiblePanels()
            InputBar()
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
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

        VStack(spacing: 6) {
            PanelToggle(
                title: "Transcrição",
                icon: "waveform",
                badge: nil,
                isExpanded: $app.showTranscript
            ) {
                TranscriptPane().frame(height: 220)
            }
            PanelToggle(
                title: "Resumo",
                icon: "list.bullet.rectangle",
                badge: app.summaryBullets.isEmpty ? nil : "\(app.summaryBullets.count)",
                isExpanded: $app.showSummary
            ) {
                SummaryPane().frame(height: 130)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

/// Toggle de painel custom (sem DisclosureGroup padrão).
private struct PanelToggle<Content: View>: View {
    let title: String
    let icon: String
    let badge: String?
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.cyan.opacity(0.9))
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.cyan)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.cyan.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassPanel(cornerRadius: 12)
    }
}

/// Pergunta/deixa mais recente do interlocutor — fixa no topo, com tradução destacada.
struct QuestionBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let q = app.currentQuestion {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.brand)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 5) {
                    Text("ELE DISSE")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Theme.violet)
                    Text(q.text)
                        .font(.system(size: 15, weight: .semibold))
                        .lineSpacing(1)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if app.brief.isForeign, let t = q.translation, !t.isEmpty {
                        Text(t.markdownAttributed)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.violet.opacity(0.25), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .animation(.spring(duration: 0.3), value: q.id)
        }
    }
}

#Preview {
    RootView().environment(AppModel())
}
