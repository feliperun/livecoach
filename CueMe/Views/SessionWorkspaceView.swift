import SwiftUI

struct SessionWorkspaceView: View {
    let record: SessionRecord
    @State private var tab: SessionWorkspaceTab = .coach
    @State private var player = MeetingPlayer()
    @State private var envelope: [Float] = []
    @State private var loadingWaveform = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                SessionWorkspaceHeader(record: record)
                WaveformPlayerView(player: player, envelope: envelope, loading: loadingWaveform)
                    .padding(.horizontal, 16).padding(.bottom, 10)
                SessionWorkspaceTabs(record: record, selection: $tab)
            }
            .background(Theme.sidebar)
            Rectangle().fill(Theme.divider).frame(height: 1)
            SessionWorkspacePane(record: record, selection: tab, player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(tab)
                .transition(.opacity)
        }
        .background(Theme.background)
        .animation(.snappy(duration: 0.18), value: tab)
        .task(id: record.id) { await loadAudio() }
        .onDisappear { player.teardown() }
    }

    private func loadAudio() async {
        player.teardown()
        envelope = []
        let selfURL = MeetingRecording.selfURL(for: record)
        let otherURL = MeetingRecording.otherURL(for: record)
        player.load(selfURL: selfURL, otherURL: otherURL)
        guard player.isReady else { loadingWaveform = false; return }
        loadingWaveform = true
        envelope = await Task.detached(priority: .userInitiated) {
            WaveformGenerator.envelope(selfURL: selfURL, otherURL: otherURL, buckets: 300)
        }.value
        loadingWaveform = false
    }
}
