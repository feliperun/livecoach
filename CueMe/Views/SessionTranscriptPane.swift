import SwiftUI

struct SessionTranscriptPane: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    let player: MeetingPlayer

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if record.transcript.isEmpty { emptyState }
                ForEach(record.transcript) { line in
                    MemoryTranscriptLine(
                        line: line,
                        speakerName: record.participantName(for: line.speaker),
                        foreign: record.isForeign,
                        active: line.id == activeLineID,
                        onTap: player.isReady ? { seek(to: line) } : nil,
                        onCorrect: { app.correctTranscript(sessionID: record.id, lineID: line.id, text: $0) }
                    )
                }
            }
            .padding(14)
        }
    }

    private var activeLineID: UUID? {
        let target = record.audioTimelineStart.addingTimeInterval(player.currentTime)
        return record.transcript.filter { $0.isFinal && $0.ts <= target }.max { $0.ts < $1.ts }?.id
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 20, weight: .light)).foregroundStyle(Theme.violet.opacity(0.7))
            Text("Sem transcrição").font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
    }

    private func seek(to line: TranscriptLine) {
        player.seek(to: line.ts.timeIntervalSince(record.audioTimelineStart))
        if !player.isPlaying { player.play() }
    }
}
