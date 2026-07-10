import SwiftUI

/// A dica do "amigo do lado" — herói da tela. Card mais novo grande, resto condensado.
struct CoachingPane: View {
    @Environment(AppModel.self) private var app

    private var cards: [CoachCard] {
        app.coachCards.reversed()   // mais novo primeiro
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !app.backendAvailable {
                MissingCLIBanner()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if cards.isEmpty {
                        EmptyCoachHint()
                    }
                    ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                        if idx == 0 {
                            HeroCard(card: card)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        } else {
                            CondensedCard(card: card)
                        }
                    }
                }
                .padding(12)
                .animation(.spring(duration: 0.35), value: cards.first?.id)
            }
        }
    }
}

/// Card principal: o que fazer AGORA. Grande, escaneável em 2 segundos.
private struct HeroCard: View {
    let card: CoachCard

    private var accent: Color {
        switch card.kind {
        case .answer: return Theme.mint
        case .correction: return Theme.amber
        case .manual: return Theme.violet
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // O cochicho do amigo.
            if !card.guidePT.isEmpty {
                Text(card.guidePT)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Frase pronta (língua da conversa) + tradução.
            if let say = card.sayConversation ?? (card.sayNative.isEmpty ? nil : card.sayNative), !say.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 7) {
                        Text("🗣️").font(.system(size: 15))
                        Text(say)
                            .font(.system(size: 16, weight: .semibold))
                            .lineSpacing(1.5)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if card.sayConversation != nil, !card.sayNative.isEmpty {
                        Text(card.sayNative)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 27)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                )
            }

            if !card.keytermsConversation.isEmpty {
                HStack(spacing: 5) {
                    ForEach(card.keytermsConversation.prefix(4), id: \.self) { term in
                        Text(term)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(accent.opacity(0.12), in: Capsule())
                            .overlay(Capsule().strokeBorder(accent.opacity(0.3), lineWidth: 1))
                    }
                }
            }

            if card.isStreaming {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("pensando…")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(accent.opacity(0.45), lineWidth: 1.5)
        )
        .shadow(color: accent.opacity(0.18), radius: 14, y: 4)
    }
}

/// Cards antigos: uma linha só, fora do caminho.
private struct CondensedCard: View {
    let card: CoachCard

    var body: some View {
        Text(card.guidePT.isEmpty ? (card.sayConversation ?? card.sayNative) : card.guidePT)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: 9)
            .opacity(0.75)
    }
}

private struct EmptyCoachHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("👋")
                .font(.system(size: 26))
            Text("Sou teu amigo do lado.")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Quando o interlocutor falar, eu cochicho aqui: o que ele quer + como responder.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineSpacing(1.5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }
}

private struct MissingCLIBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            Text("Claude Code CLI não encontrado — só transcrição.")
                .font(.system(size: 11))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.amber.opacity(0.12))
    }
}
