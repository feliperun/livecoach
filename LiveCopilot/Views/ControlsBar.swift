import SwiftUI

/// Header fino: status, captura do interlocutor, pin, silêncio, ajustes, iniciar/parar.
struct HeaderBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        HStack(spacing: 10) {
            Circle()
                .fill(app.isRunning ? .green : .secondary)
                .frame(width: 8, height: 8)
            Text(app.statusText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(app.isRunning ? .primary : .secondary)
                .lineLimit(1)

            if app.isRunning {
                CaptureBadge(active: app.systemCaptureActive) {
                    app.openScreenRecordingSettings()
                }
            }

            Spacer()

            Toggle(isOn: $app.pinned) {
                Image(systemName: app.pinned ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            .help("Janela sempre no topo")

            Toggle(isOn: Binding(get: { app.silenceMode }, set: { _ in app.toggleSilence() })) {
                Image(systemName: app.silenceMode ? "speaker.slash" : "speaker.wave.2")
            }
            .toggleStyle(.button)
            .help("Pausa o coach, mantém a transcrição")

            Button {
                app.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Brief da sessão: modo, idiomas, modelo, CV")
            .disabled(app.isRunning)

            Button(app.isRunning ? "Parar" : "Iniciar") {
                app.isRunning ? app.stop() : app.start()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .tint(app.isRunning ? .red : .accentColor)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Campo de pergunta manual, colado na base.
struct InputBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        HStack(spacing: 8) {
            TextField("Pergunta rápida pro coach…", text: $app.manualInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit { app.ask() }
            Button {
                app.ask()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(app.manualInput.trimmingCharacters(in: .whitespaces).isEmpty || !app.isRunning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Estado da captura do interlocutor. Clicável quando falta permissão.
private struct CaptureBadge: View {
    let active: Bool
    let fix: () -> Void

    var body: some View {
        Button(action: { if !active { fix() } }) {
            HStack(spacing: 4) {
                Image(systemName: active ? "headphones" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text(active ? "Interlocutor" : "Só você — corrigir")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(active ? .green : .orange)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((active ? Color.green : Color.orange).opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(active
              ? "Capturando o áudio do interlocutor (sistema)."
              : "Sem áudio de sistema. Clique pra abrir Ajustes → Gravação de Tela e Áudio do Sistema, aprove o LiveCopilot e reinicie a sessão.")
    }
}
