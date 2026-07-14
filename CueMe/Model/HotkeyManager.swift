import AppKit

/// Atalho ⌥Space (global + local) para mostrar/ocultar a janela — some/aparece o
/// copiloto sem tirar o foco da call. O monitor global só dispara com foco fora
/// se a permissão de Input Monitoring existir; o local cobre quando o app tem foco.
@MainActor
final class HotkeyManager {
    var onToggle: () -> Void = {}

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let spaceKeyCode: UInt16 = 49

    func start() {
        stop()
        let matches: (NSEvent) -> Bool = { [spaceKeyCode] event in
            event.keyCode == spaceKeyCode
                && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if matches(event) { self?.onToggle() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if matches(event) { self?.onToggle(); return nil }
            return event
        }
    }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
    }

    /// Alterna visibilidade da janela principal.
    static func toggleMainWindow() {
        let windows = NSApp.windows.filter { $0.canBecomeMain && !$0.isMiniaturized }
        guard let window = windows.first ?? NSApp.windows.first else { return }
        if window.isVisible && NSApp.isActive {
            window.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func showMainWindow() {
        let windows = NSApp.windows.filter { $0.canBecomeMain && !$0.isMiniaturized }
        guard let window = windows.first ?? NSApp.windows.first else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
