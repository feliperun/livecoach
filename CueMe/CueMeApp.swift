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
                .frame(minWidth: 760, minHeight: 560)
                .task { delegate.connect(app) }
                .onOpenURL { url in
                    Task { await app.handleExternalURL(url) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_020, height: 760)
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
    private weak var app: AppModel?
    private var pendingFileURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkeys.onToggle = { HotkeyManager.toggleMainWindow() }
        hotkeys.start()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(externalAudioReady),
            name: .cueMeExternalAudioReady,
            object: nil
        )
    }

    func connect(_ app: AppModel) {
        self.app = app
        let files = pendingFileURLs
        pendingFileURLs.removeAll()
        Task {
            if !files.isEmpty { await app.importAudioFiles(files) }
            await app.consumeExternalAudioInbox()
        }
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        guard let app else { return }
        Task {
            app.reloadWorkspaceFromDisk()
            await app.consumeExternalAudioInbox()
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map(URL.init(fileURLWithPath:))
        if let app {
            Task { await app.importAudioFiles(urls) }
        } else {
            pendingFileURLs.append(contentsOf: urls)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    @objc private func externalAudioReady() {
        guard let app else { return }
        Task { await app.consumeExternalAudioInbox() }
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
        Button("Histórico de sessões") {
            app.sidebarCollapsed = false
            HotkeyManager.showMainWindow()
        }
        Button("Sobre o CueMe") { openWindow(id: "about") }
        Button("Sair") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
