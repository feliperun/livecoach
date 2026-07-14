import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HistoryExportToolbar: ToolbarContent {
    let record: SessionRecord
    @State private var copied = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button(copied ? "Copiado ✓" : "Copiar JSON", systemImage: "doc.on.doc") { copyJSON() }
                Button("Exportar JSON…", systemImage: "square.and.arrow.down") { exportJSON() }
            } label: {
                Label("Exportar", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func copyJSON() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.prettyJSON, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = record.exportFilename
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? record.prettyJSON.data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }
}
