import SwiftUI

struct ControlsBar: View {
    @Environment(AppModel.self) private var app

    private let langs = ["pt-BR", "en-US", "es-ES", "fr-FR", "de-DE", "it-IT"]

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Picker("Modo", selection: $app.brief.mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 170)
                .disabled(app.isRunning)

                Picker("Conversa", selection: $app.brief.conversationLang) {
                    ForEach(langs, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 135)
                .disabled(app.isRunning)

                Picker("Nativo", selection: $app.brief.nativeLang) {
                    ForEach(langs, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 135)
                .disabled(app.isRunning)

                Picker("Coach", selection: $app.coachModel) {
                    ForEach(CoachModel.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 170)
                .disabled(app.isRunning)
                .help("Modelo do live coach. Opus = mais profundo; Sonnet = mais rápido.")

                Spacer()

                if app.isRunning {
                    CaptureBadge(active: app.systemCaptureActive)
                }

                Text(app.statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(app.isRunning ? .green : .secondary)

                Button(app.isRunning ? "Parar" : "Iniciar") {
                    app.isRunning ? app.stop() : app.start()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .tint(app.isRunning ? .red : .accentColor)

                Toggle(isOn: Binding(get: { app.silenceMode }, set: { _ in app.toggleSilence() })) {
                    Label("Silêncio", systemImage: app.silenceMode ? "speaker.slash" : "speaker.wave.2")
                }
                .toggleStyle(.button)
                .help("Pausa o coach, mantém a transcrição")
            }

            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .foregroundStyle(.secondary)
                TextField("Dúvida no meio da conversa → coach (Sonnet)…", text: $app.manualInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
                    .onSubmit { app.ask() }
                Button("Perguntar") { app.ask() }
                    .disabled(app.manualInput.trimmingCharacters(in: .whitespaces).isEmpty || !app.isRunning)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// Indica se o áudio do interlocutor (ScreenCaptureKit) está sendo capturado.
private struct CaptureBadge: View {
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: active ? "headphones" : "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(active ? "Interlocutor" : "Só você")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(active ? .green : .orange)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background((active ? Color.green : Color.orange).opacity(0.14), in: Capsule())
        .help(active
              ? "Capturando o áudio do interlocutor (sistema)."
              : "Sem áudio de sistema — aprove 'Screen & System Audio Recording' em Ajustes p/ ouvir o interlocutor.")
    }
}
