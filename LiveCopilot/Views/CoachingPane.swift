import SwiftUI

struct CoachingPane: View {
    @Environment(AppModel.self) private var app

    private var cards: [CoachCard] {
        app.coachCards.reversed()   // mais novo no topo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Coach", systemImage: "sparkles")

            if !app.backendAvailable {
                MissingCLIBanner()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if cards.isEmpty {
                        Text("As sugestões aparecem aqui quando o interlocutor fala.")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                        CoachCardView(card: card, highlighted: idx == 0)
                    }
                }
                .padding(14)
            }
        }
    }
}

private struct CoachCardView: View {
    let card: CoachCard
    let highlighted: Bool

    private var accent: Color {
        switch card.kind {
        case .answer: return .green
        case .correction: return .orange
        case .manual: return .indigo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // GUIA — a orientação, grande e escaneável.
            if !card.guidePT.isEmpty {
                Text("🎯 \(card.guidePT)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // DIGA — a frase pronta na língua da conversa (o mais importante).
            if let say = card.sayConversation ?? (card.sayNative.isEmpty ? nil : card.sayNative), !say.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("🗣️").font(.system(size: 20))
                        Text(say)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // Tradução nativa da frase (vocabulário).
                    if card.sayConversation != nil, !card.sayNative.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Text("💬").font(.system(size: 15))
                            Text(card.sayNative)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            // KEYTERMS — vocabulário-chave.
            if !card.keytermsConversation.isEmpty {
                HStack(spacing: 6) {
                    Text("🔑").font(.system(size: 13))
                    ForEach(card.keytermsConversation, id: \.self) { term in
                        Text(term)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(accent.opacity(0.18), in: Capsule())
                    }
                }
            }

            if card.isStreaming {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("pensando…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(highlighted ? accent.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(accent.opacity(highlighted ? 0.55 : 0.2), lineWidth: highlighted ? 2 : 1)
        )
    }
}

private struct MissingCLIBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Claude Code CLI não encontrado — só transcrição. Instale/logue com `claude`.")
                .font(.system(size: 12))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.orange.opacity(0.12))
    }
}
