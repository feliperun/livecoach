import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Histórico de sessões (treino e conversa real) — lista → detalhe read-only.
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selected: SessionRecord?

    var body: some View {
        NavigationStack {
            Group {
                if app.history.isEmpty {
                    ContentUnavailableView(
                        "Sem sessões ainda",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Quando você parar uma sessão, ela aparece aqui pra revisar.")
                    )
                } else {
                    List {
                        ForEach(app.history) { rec in
                            NavigationLink(value: rec) { HistoryRow(record: rec) }
                                .swipeActions {
                                    Button(role: .destructive) { app.deleteHistory(rec.id) } label: {
                                        Label("Apagar", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button("Copiar JSON", systemImage: "doc.on.doc") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(rec.prettyJSON, forType: .string)
                                    }
                                    Button("Apagar", systemImage: "trash", role: .destructive) {
                                        app.deleteHistory(rec.id)
                                    }
                                }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Histórico")
            .navigationDestination(for: SessionRecord.self) { HistorySessionDetailView(record: $0) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluir") { dismiss() }
                }
            }
        }
        .frame(width: 560, height: 640)
    }
}

private struct HistoryRow: View {
    let record: SessionRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.training ? "graduationcap.fill" : "waveform")
                .font(.system(size: 15))
                .foregroundStyle(record.training ? Theme.violet : Theme.cyan)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("· \(record.mode.label)")
                    Text("· \(record.turnCount) turnos")
                    Text("· \(durationText)")
                    if record.hasAudio {
                        Image(systemName: "waveform")
                            .foregroundStyle(Theme.mint)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var durationText: String {
        let m = Int(record.duration) / 60, s = Int(record.duration) % 60
        return m > 0 ? "\(m)m\(s)s" : "\(s)s"
    }
}
