import SwiftUI
import AppKit

/// A dica do "amigo do lado" — herói da tela. Card mais novo grande, resto condensado.
struct CoachingPane: View {
    @Environment(AppModel.self) private var app

    private var latest: CoachCard? { app.activeCoachCard }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !app.backendAvailable {
                MissingBackendBanner(model: app.coachModel)
            } else if let error = app.coachBackendError {
                BackendErrorBanner(error: error)
            }

            Group {
                if let latest {
                    HeroCard(card: latest, convLang: app.brief.conversationLang, keyterms: app.brief.keyterms)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    EmptyCoachHint(
                        model: app.coachModel,
                        ready: app.coachBackendReady,
                        sessionState: app.sessionState
                    )
                }
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(.spring(duration: 0.35), value: latest?.id)
        }
    }
}

/// Card principal: **o que dizer AGORA** é o herói (maior). GUIA é contexto curto.
private struct HeroCard: View {
    let card: CoachCard
    let convLang: String
    let keyterms: [String]

    private var accent: Color {
        switch card.kind {
        case .answer: return Theme.mint
        case .correction: return Theme.amber
        case .manual: return Theme.violet
        }
    }

    private var phrase: String? {
        let p = card.sayConversation ?? (card.sayNative.isEmpty ? nil : card.sayNative)
        return (p?.isEmpty ?? true) ? nil : p
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Uma única pista visual. Enquanto a rede responde, esta é local.
            if !card.guidePT.isEmpty {
                Text(card.guidePT)
                    .font(.system(size: phrase == nil ? 18 : 12, weight: .bold, design: .rounded))
                    .foregroundStyle(phrase == nil ? accent : .secondary)
                    .lineLimit(1)
                    .padding(.horizontal, phrase == nil ? 0 : 8)
                    .padding(.vertical, phrase == nil ? 0 : 4)
                    .background(
                        phrase == nil ? Color.clear : accent.opacity(0.1),
                        in: Capsule()
                    )
            }

            // A frase falável é o único conteúdo textual dominante.
            if let say = phrase {
                HStack(alignment: .top, spacing: 10) {
                    Text(highlighted(say))
                        .lineSpacing(2)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    CopyButton(text: say, accent: accent)
                }
            }

            // O spinner é secundário; nunca compete com a pista/frase.
            if card.isStreaming, phrase == nil, card.guidePT.isEmpty {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("preparando sua deixa…")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if card.isStreaming {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("refinando…").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.45), lineWidth: 1.5))
        .shadow(color: accent.opacity(0.14), radius: 10, y: 3)
    }

    /// Realça a frase (língua da conversa) — termos-chave/nomes/números destacam.
    private func highlighted(_ say: String) -> AttributedString {
        if card.sayConversation != nil {
            return Highlighter.translation(say, native: convLang, keyterms: keyterms, base: 23)
        }
        var a = AttributedString(say)
        a.font = .system(size: 23, weight: .bold, design: .rounded)
        return a
    }
}

/// Botão de copiar a frase (1 clique → área de transferência).
private struct CopyButton: View {
    let text: String
    let accent: Color
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(copied ? Theme.mint : accent)
                .frame(width: 26, height: 26)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Copiar a frase")
    }
}

private struct EmptyCoachHint: View {
    let model: CoachModel
    let ready: Bool
    let sessionState: SessionState

    private var provider: String { model.isDeepSeek ? "DeepSeek" : "Claude" }
    private var status: CoachConnectionPresentation {
        .resolve(provider: provider, state: sessionState, ready: ready)
    }

    var body: some View {
        HStack(spacing: 8) {
            if status.showsProgress {
                ProgressView().controlSize(.small)
            } else if status.isReady {
                Circle().fill(Theme.mint).frame(width: 8, height: 8)
            } else {
                Circle().fill(Color.secondary.opacity(0.55)).frame(width: 8, height: 8)
            }
            Text(status.label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }
}

/// Mantém o estado vazio honesto: o backend só aquece depois que uma sessão começa.
/// Portanto, `idle` nunca deve parecer uma conexão presa.
struct CoachConnectionPresentation: Equatable {
    let label: String
    let showsProgress: Bool
    let isReady: Bool

    static func resolve(provider: String, state: SessionState, ready: Bool) -> Self {
        switch state {
        case .idle:
            return .init(label: "Pronto para iniciar", showsProgress: false, isReady: false)
        case .preparing, .running:
            if ready {
                return .init(label: "\(provider) pronto", showsProgress: false, isReady: true)
            }
            return .init(label: "Conectando \(provider)…", showsProgress: true, isReady: false)
        case .paused:
            return .init(label: "Sessão pausada", showsProgress: false, isReady: ready)
        case .stopping:
            return .init(label: "Salvando…", showsProgress: true, isReady: false)
        case .error:
            return .init(label: "Tente novamente", showsProgress: false, isReady: false)
        }
    }
}

private struct BackendErrorBanner: View {
    let error: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Theme.rose)
            Text("Coach offline")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.rose.opacity(0.12))
        .help(error)
    }
}

private struct MissingBackendBanner: View {
    let model: CoachModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            Text(model.isDeepSeek ? "Configure a DeepSeek." : "Claude CLI não encontrado.")
                .font(.system(size: 11))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.amber.opacity(0.12))
    }
}
