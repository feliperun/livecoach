import SwiftUI

/// Header fino: status, captura do interlocutor, pin, silêncio, ajustes, iniciar/parar.
struct HeaderBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        HStack(spacing: 8) {
            // Espaço pros semáforos da janela (título escondido).
            Spacer().frame(width: 58)

            PulseDot(active: app.isRunning)
            Text(app.statusText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
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
            .buttonStyle(IconButtonStyle(isOn: app.pinned))
            .help("Janela sempre no topo")

            Toggle(isOn: Binding(get: { app.silenceMode }, set: { _ in app.toggleSilence() })) {
                Image(systemName: app.silenceMode ? "moon.fill" : "moon")
            }
            .toggleStyle(.button)
            .buttonStyle(IconButtonStyle(isOn: app.silenceMode))
            .help("Modo silêncio: pausa o coach, mantém a transcrição")

            Button {
                app.showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(IconButtonStyle())
            .help("Brief da sessão: modo, idiomas, modelo, CV")
            .disabled(app.isRunning)

            Button(app.isRunning ? "Parar" : "Iniciar") {
                app.isRunning ? app.stop() : app.start()
            }
            .buttonStyle(PrimaryButtonStyle(danger: app.isRunning))
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// Campo de pergunta manual, colado na base.
struct InputBar: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var app = app

        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.cyan.opacity(0.8))
            TextField("Pergunta rápida pro coach…", text: $app.manualInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { app.ask() }
            Button {
                app.ask()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .background(Theme.brand, in: Circle())
                    .opacity(sendDisabled ? 0.3 : 1)
            }
            .buttonStyle(.plain)
            .disabled(sendDisabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                focused ? Theme.cyan.opacity(0.5) : Theme.surfaceStroke,
                lineWidth: 1
            )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var sendDisabled: Bool {
        app.manualInput.trimmingCharacters(in: .whitespaces).isEmpty || !app.isRunning
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
                    .font(.system(size: 9))
                Text(active ? "Interlocutor" : "Só você — corrigir")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(active ? Theme.mint : Theme.amber)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((active ? Theme.mint : Theme.amber).opacity(0.13), in: Capsule())
            .overlay(Capsule().strokeBorder((active ? Theme.mint : Theme.amber).opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(active
              ? "Capturando o áudio do interlocutor (sistema)."
              : "Sem áudio de sistema. Clique pra abrir Ajustes → Gravação de Tela e Áudio do Sistema, aprove o LiveCopilot e reinicie a sessão.")
    }
}
