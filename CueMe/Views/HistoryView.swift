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
            .navigationDestination(for: SessionRecord.self) { SessionDetailView(record: $0) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluir") { dismiss() }
                }
            }
        }
        .frame(width: 560, height: 640)
        .preferredColorScheme(.dark)
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

/// Detalhe read-only: pergunta/coach/transcrição da sessão salva.
private struct SessionDetailView: View {
    let record: SessionRecord
    @State private var copied = false
    @State private var player = MeetingPlayer()
    @State private var envelope: [Float] = []
    @State private var loadingWaveform = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if record.hasAudio {
                    WaveformPlayerView(player: player, envelope: envelope, loading: loadingWaveform)
                }

                if !record.coachCards.isEmpty {
                    section("Coach") {
                        ForEach(record.coachCards.reversed()) { c in SavedCoachCard(card: c) }
                    }
                }
                if !record.summaryBullets.isEmpty {
                    section("Resumo") {
                        ForEach(Array(record.summaryBullets.enumerated()), id: \.offset) { _, b in
                            HStack(alignment: .top, spacing: 6) { Text("•").foregroundStyle(.secondary); Text(b) }
                                .font(.system(size: 13))
                        }
                    }
                }
                section("Transcrição") {
                    ForEach(record.transcript) { line in
                        SavedLine(
                            line: line,
                            foreign: record.isForeign,
                            active: record.hasAudio && line.id == activeLineID,
                            onTap: record.hasAudio ? { seek(to: line) } : nil
                        )
                    }
                }
            }
            .padding(18)
        }
        .background(Theme.background)
        .navigationTitle(record.training ? "Treino" : record.mode.label)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(copied ? "Copiado ✓" : "Copiar JSON", systemImage: "doc.on.doc") { copyJSON() }
                    Button("Exportar JSON…", systemImage: "square.and.arrow.down") { exportJSON() }
                } label: {
                    Label("Exportar", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task {
            guard record.hasAudio else { return }
            let selfURL = MeetingRecording.selfURL(for: record.id)
            let otherURL = MeetingRecording.otherURL(for: record.id)
            player.load(selfURL: selfURL, otherURL: otherURL)
            envelope = await Task.detached(priority: .userInitiated) {
                WaveformGenerator.envelope(selfURL: selfURL, otherURL: otherURL, buckets: 260)
            }.value
            loadingWaveform = false
        }
        .onDisappear { player.teardown() }
    }

    /// Linha da transcrição correspondente ao instante de reprodução atual.
    private var activeLineID: UUID? {
        guard player.currentTime > 0 else { return nil }
        let target = record.audioTimelineStart.addingTimeInterval(player.currentTime)
        return record.transcript
            .filter { $0.isFinal && $0.ts <= target }
            .max(by: { $0.ts < $1.ts })?.id
    }

    private func seek(to line: TranscriptLine) {
        player.seek(to: line.ts.timeIntervalSince(record.audioTimelineStart))
        if !player.isPlaying { player.play() }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.title).font(.system(size: 16, weight: .bold))
            Text("\(record.startedAt.formatted(date: .long, time: .shortened)) · \(record.mode.label)\(record.training ? " · treino" : "")")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(Theme.cyan)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SavedCoachCard: View {
    let card: CoachCard
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !card.guidePT.isEmpty {
                Text("🎯 \(card.guidePT)").font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            if let say = card.sayConversation ?? (card.sayNative.isEmpty ? nil : card.sayNative) {
                Text("🗣️ \(say)").font(.system(size: 14, weight: .semibold)).textSelection(.enabled)
            }
            if !card.keytermsConversation.isEmpty {
                Text("🔑 " + card.keytermsConversation.joined(separator: " · "))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.mint)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 10)
    }
}

private struct SavedLine: View {
    let line: TranscriptLine
    let foreign: Bool
    var active: Bool = false
    var onTap: (() -> Void)? = nil
    private var color: Color { line.speaker == .self ? Theme.cyan : Theme.violet }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if onTap != nil {
                Image(systemName: active ? "speaker.wave.2.fill" : "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(active ? Theme.mint : .clear)
                    .frame(width: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(line.speaker.label.uppercased())
                    .font(.system(size: 8.5, weight: .heavy)).foregroundStyle(color)
                Text(line.text).font(.system(size: 13)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if foreign, let t = line.translation, !t.isEmpty {
                    Text(t).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(active ? Theme.mint.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}
