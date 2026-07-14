import SwiftUI
import AppKit

@main
struct CueMeApp: App {
    @State private var app = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .frame(minWidth: 380, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 460, height: 720)
        .commands {
            AboutCommand()
            CommandGroup(after: .windowArrangement) {
                Button("Mostrar/Ocultar CueMe") { HotkeyManager.toggleMainWindow() }
                    .keyboardShortcut(.space, modifiers: [.option])
            }
        }

        Window("Sobre o CueMe", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("CueMe Rail", id: "camera-rail") {
            CameraRailView().environment(app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .defaultPosition(.top)

        MenuBarExtra("CueMe", systemImage: app.isRunning ? "waveform.badge.mic" : "waveform") {
            MenuBarContent().environment(app)
        }
    }
}

/// Substitui o "Sobre" padrão do menu do app pela nossa tela.
private struct AboutCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Sobre o CueMe") { openWindow(id: "about") }
        }
    }
}

/// Instala o atalho global ⌥Space no launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let hotkeys = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkeys.onToggle = { HotkeyManager.toggleMainWindow() }
        hotkeys.start()
    }
}

/// Conteúdo do menu na barra: status + controles rápidos.
private struct MenuBarContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(app.isRunning ? "● Ao vivo" : "○ Pronto")

        Button(app.isRunning ? "Parar" : "Iniciar") {
            app.isRunning ? app.stop() : app.start()
        }
        Button("Mostrar / Ocultar") { HotkeyManager.toggleMainWindow() }
            .keyboardShortcut(.space, modifiers: [.option])

        if app.isRunning {
            Toggle("Modo silêncio", isOn: Binding(get: { app.silenceMode }, set: { _ in app.toggleSilence() }))
            if !app.systemCaptureActive {
                Button("Corrigir captura do interlocutor…") { app.openScreenRecordingSettings() }
            }
        }

        Divider()
        Button("Buscar atualizações…") { app.checkForUpdates() }
        Button("Abrir Camera Rail") { openWindow(id: "camera-rail") }
        Button("Testar setup") { app.showPreflight = true }
        Button("Histórico de sessões") { app.showHistory = true }
        Button("Sobre o CueMe") { openWindow(id: "about") }
        Button("Sair") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
