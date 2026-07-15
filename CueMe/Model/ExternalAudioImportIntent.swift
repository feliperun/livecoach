import AppIntents
import Foundation
import UniformTypeIdentifiers

struct ImportMeetingAudioIntent: AppIntent {
    static let title: LocalizedStringResource = "Importar áudio no CueMe"
    static let description = IntentDescription(
        "Importa uma gravação para transcrição, ata, notas e tarefas no CueMe."
    )
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(
        title: "Áudio",
        supportedContentTypes: [.audio],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var files: [IntentFile]

    static var parameterSummary: some ParameterSummary {
        Summary("Importar \(\.$files) no CueMe")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        for file in files {
            try ExternalAudioInbox.enqueue(data: file.data, filename: file.filename)
        }
        return .result(dialog: "Áudio enviado ao CueMe.")
    }
}

struct CueMeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ImportMeetingAudioIntent(),
            phrases: ["Importar áudio no \(.applicationName)"],
            shortTitle: "Importar áudio",
            systemImageName: "waveform.badge.plus"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .purple }
}
