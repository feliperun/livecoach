import SwiftUI

/// Painel do modo "Gravar reunião": tema livre, coach desligado (pouco eficaz aqui).
/// Mostra status de gravação/transcrição ao vivo — sem cochichos, só captura limpa.
struct MeetingPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                RecordingBadge(
                    recording: app.recordAudio,
                    elapsed: elapsed(at: timeline.date)
                )
            }

            VStack(spacing: 5) {
                Text("Modo reunião")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(app.recordAudio
                     ? "Tema livre. Transcrevendo e gravando os dois lados — sem coach."
                     : "Tema livre. Transcrevendo — sem coach. Gravação de áudio desligada.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
            }

            HStack(spacing: 18) {
                StatTile(value: "\(app.transcript.filter(\.isFinal).count)", label: "linhas")
                StatTile(value: "\(app.summaryBullets.count)", label: "notas")
            }

            if let last = app.transcript.last(where: { $0.isFinal }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(last.speaker.label.uppercased())
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(last.speaker == .self ? Theme.cyan : Theme.violet)
                    Text(last.text)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(10)
                .frame(maxWidth: 320, alignment: .leading)
                .glassPanel(cornerRadius: 10)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private func elapsed(at now: Date) -> TimeInterval {
        guard let start = app.sessionStartTime else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }
}

private struct RecordingBadge: View {
    let recording: Bool
    let elapsed: TimeInterval

    private var timeText: String {
        let m = Int(elapsed) / 60, s = Int(elapsed) % 60
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill((recording ? Theme.rose : Theme.cyan).opacity(0.12))
                    .frame(width: 88, height: 88)
                PulseDot(active: true)
                    .scaleEffect(2.2)
            }
            HStack(spacing: 6) {
                if recording {
                    Circle().fill(Theme.rose).frame(width: 7, height: 7)
                    Text("REC").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.rose)
                } else {
                    Image(systemName: "waveform").font(.system(size: 10)).foregroundStyle(Theme.cyan)
                    Text("AO VIVO").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.cyan)
                }
                Text(timeText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
    }
}
