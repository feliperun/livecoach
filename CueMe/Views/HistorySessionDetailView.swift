import SwiftUI

/// Read-only detail retained for the legacy History window.
struct HistorySessionDetailView: View {
    let record: SessionRecord
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
                        ForEach(record.coachCards.reversed()) { card in SavedHistoryCoachCard(card: card) }
                    }
                }
                if !record.summaryBullets.isEmpty {
                    section("Resumo") {
                        ForEach(Array(record.summaryBullets.enumerated()), id: \.offset) { _, bullet in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").foregroundStyle(.secondary)
                                Text(bullet)
                            }
                            .font(.system(size: 13))
                        }
                    }
                }
                if !record.diagnostics.events.isEmpty { HistoryDiagnosticsSection(record: record) }
                section("Transcrição") {
                    ForEach(record.transcript) { line in
                        SavedHistoryLine(
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
        .toolbar { HistoryExportToolbar(record: record) }
        .task { await loadAudio() }
        .onDisappear { player.teardown() }
    }

    private var activeLineID: UUID? {
        guard player.currentTime > 0 else { return nil }
        let target = record.audioTimelineStart.addingTimeInterval(player.currentTime)
        return record.transcript.filter { $0.isFinal && $0.ts <= target }.max { $0.ts < $1.ts }?.id
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.title).font(.system(size: 16, weight: .bold))
            Text("\(record.startedAt.formatted(date: .long, time: .shortened)) · \(record.mode.label)\(record.training ? " · treino" : "")")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func seek(to line: TranscriptLine) {
        player.seek(to: line.ts.timeIntervalSince(record.audioTimelineStart))
        if !player.isPlaying { player.play() }
    }

    private func loadAudio() async {
        guard record.hasAudio else { return }
        let selfURL = MeetingRecording.selfURL(for: record)
        let otherURL = MeetingRecording.otherURL(for: record)
        player.load(selfURL: selfURL, otherURL: otherURL)
        envelope = await Task.detached(priority: .userInitiated) {
            WaveformGenerator.envelope(selfURL: selfURL, otherURL: otherURL, buckets: 260)
        }.value
        loadingWaveform = false
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(Theme.cyan)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
