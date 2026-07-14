import SwiftUI
import Translation

/// Unified live and review workspace with an always-visible session rail.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        // Capturado fora do closure de tradução: o closure só toca este pipe (Sendable),
        // nunca o AppModel (MainActor) — assim a session não "vaza" de isolamento.
        let pipe = app.translationPipe

        HStack(spacing: 0) {
            SessionSidebar()
            Divider().opacity(0.45)

            VStack(spacing: 0) {
                HeaderBar()
                if let record = app.selectedSession {
                    SessionWorkspaceView(record: record)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LiveWorkspace()
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .translationTask(app.translationConfig) { session in
            nonisolated(unsafe) let s = session
            await pipe.run(session: s)
        }
        .sheet(isPresented: $app.showSettings) {
            BriefEditor()
        }
        .sheet(isPresented: $app.showPreflight) {
            PreflightView()
        }
    }
}

private struct LiveWorkspace: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            CaptureHealthAlert()

            if isPristineIdle {
                SessionLaunchView()
                    .frame(maxHeight: .infinity)
            } else if app.brief.mode.isPassive {
                MeetingPanel()
                    .frame(maxHeight: .infinity)
            } else {
                QuestionBanner()
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                CoachingPane()
                    .frame(maxHeight: .infinity)
            }

            if !isPristineIdle {
                CollapsiblePanels()
                if !app.brief.mode.isPassive { InputBar() }
            }
            if app.sessionStartTime != nil {
                LiveTransportBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.24), value: app.sessionStartTime != nil)
    }

    private var isPristineIdle: Bool {
        app.sessionState == .idle && app.transcript.isEmpty && app.coachCards.isEmpty
    }
}

private struct SessionLaunchView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(Theme.violet.opacity(0.06)).frame(width: 150, height: 150)
                Circle().strokeBorder(Theme.violet.opacity(0.12), lineWidth: 1).frame(width: 112, height: 112)
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.brand)
                    .symbolEffect(.breathe, options: .repeating.speed(0.45))
            }

            VStack(spacing: 7) {
                Text(app.brief.mode.isPassive ? "Sua reunião, lembrada." : "Converse. O CueMe acompanha.")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(app.brief.mode.isPassive
                     ? "Áudio nítido, transcrição e próximos passos."
                     : "Dicas ao vivo e uma memória completa depois.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                capability("waveform", "Grava")
                capability("captions.bubble", "Transcreve")
                capability("brain.head.profile", "Lembra")
            }

            Label("⌘ ↩ para iniciar", systemImage: "keyboard")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func capability(_ icon: String, _ label: String) -> some View {
        Label(label, systemImage: icon)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Theme.interactive, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.divider))
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
                badge: app.summaryBackendError != nil
                    ? "!"
                    : (app.summaryBullets.isEmpty ? nil : "\(app.summaryBullets.count)"),
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
                withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
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
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.violet)
                Text(displayText(for: q))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineSpacing(1)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.violet.opacity(0.25), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .animation(.snappy(duration: 0.22), value: q.id)
            .help(q.text)
        }
    }

    private func displayText(for line: TranscriptLine) -> String {
        if app.brief.isForeign, let translation = line.translation, !translation.isEmpty {
            return translation
        }
        return line.text
    }
}

#Preview {
    RootView().environment(AppModel())
}
