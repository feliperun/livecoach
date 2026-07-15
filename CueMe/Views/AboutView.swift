import SwiftUI
import AppKit

/// Tela "Sobre" — ícone, versão, links e créditos.
struct AboutView: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "Versão \(v) (\(b))"
    }

    private var cliOK: Bool { ClaudeClient().isAvailable }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
                .shadow(color: Theme.violet.opacity(0.4), radius: 16, y: 4)

            VStack(spacing: 4) {
                Text("CueMe")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                Text(version)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text("Seu segundo cérebro file-first: escreva, grave e conecte o que vive — com uma memória que também pode ajudar em tempo real.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            HStack(spacing: 6) {
                Image(systemName: cliOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(cliOK ? Theme.mint : Theme.amber)
                Text(cliOK ? "Claude Code CLI conectado" : "Claude Code CLI não encontrado")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((cliOK ? Theme.mint : Theme.amber).opacity(0.12), in: Capsule())

            HStack(spacing: 10) {
                LinkButton(title: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right",
                           url: "https://github.com/feliperun/cueme")
                LinkButton(title: "Site", systemImage: "globe",
                           url: "https://feliperun.github.io/cueme/")
            }
            .padding(.top, 2)

            Divider().padding(.horizontal, 24)

            VStack(spacing: 3) {
                Text("Swift nativo · macOS 26 · Markdown soberano · IA opcional")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Text("MIT · Construído com Swift + Claude Code")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(26)
        .frame(width: 360)
        .background(Theme.background)
    }
}

private struct LinkButton: View {
    let title: String
    let systemImage: String
    let url: String

    var body: some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

#Preview { AboutView() }
