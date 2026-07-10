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
                        } else {
                            CondensedCard(card: card)
                        }
                    }
                }
                .padding(12)
            }
        }
    }
}

/// Card principal: o que fazer AGORA. Grande, escaneável em 2 segundos.
private struct HeroCard: View {
    let card: CoachCard

    private var accent: Color {
        switch card.kind {
        case .answer: return .green
        case .correction: return .orange
        case .manual: return .indigo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // O cochicho do amigo.
            if !card.guidePT.isEmpty {
                Text(card.guidePT)
                    .font(.system(size: 17, weight: .bold))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Frase pronta (língua da conversa) + tradução.
            if let say = card.sayConversation ?? (card.sayNative.isEmpty ? nil : card.sayNative), !say.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 6) {
                        Text("🗣️").font(.system(size: 16))
                        Text(say)
                            .font(.system(size: 17, weight: .semibold))
                            .lineSpacing(1)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if card.sayConversation != nil, !card.sayNative.isEmpty {
                        Text(card.sayNative)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 26)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            }

            if !card.keytermsConversation.isEmpty {
                HStack(spacing: 5) {
                    Text("🔑").font(.system(size: 11))
                    ForEach(card.keytermsConversation.prefix(4), id: \.self) { term in
                        Text(term)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(accent.opacity(0.16), in: Capsule())
                    }
                }
            }

            if card.isStreaming {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("pensando…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.5), lineWidth: 1.5))
    }
}

/// Cards antigos: uma linha só, fora do caminho.
private struct CondensedCard: View {
    let card: CoachCard

    var body: some View {
        Text(card.guidePT.isEmpty ? (card.sayConversation ?? card.sayNative) : card.guidePT)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmptyCoachHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("👋 Sou teu amigo do lado.")
                .font(.system(size: 15, weight: .semibold))
            Text("Quando o interlocutor falar, eu cochicho aqui: o que ele quer + como responder.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

private struct MissingCLIBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Claude Code CLI não encontrado — só transcrição.")
                .font(.system(size: 11))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.orange.opacity(0.12))
    }
}
