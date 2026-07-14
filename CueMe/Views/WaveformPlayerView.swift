import SwiftUI

/// Player visual do áudio original da sessão — waveform + transporte. Usado no
/// detalhe do histórico; o tempo de reprodução é lido pelo pai pra destacar a
/// linha ativa da transcrição em sincronia.
struct WaveformPlayerView: View {
    @Bindable var player: MeetingPlayer
    let envelope: [Float]
    let loading: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.togglePlay()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 38, height: 38)
                    .background(Theme.violet, in: Circle())
                    .shadow(color: Theme.violet.opacity(0.2), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(!player.isReady)
            .opacity(player.isReady ? 1 : 0.28)

            VStack(alignment: .leading, spacing: 4) {
                if loading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("gerando forma de onda…")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    .frame(height: 40)
                } else if !player.isReady {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.slash")
                        Text("Áudio indisponível")
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                } else {
                    WaveformCanvas(envelope: envelope, progress: progress) { fraction in
                        player.seek(to: fraction * player.duration)
                    }
                    .frame(height: 40)
                }
                HStack {
                    Text(Self.timeText(player.currentTime))
                    Spacer()
                    Text(Self.timeText(player.duration))
                }
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            }
        }
        .padding(12)
        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.divider))
    }

    private var progress: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(player.currentTime / player.duration)
    }

    private static func timeText(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Barras de amplitude + linha de playhead + arrastar pra buscar.
private struct WaveformCanvas: View {
    let envelope: [Float]
    let progress: CGFloat
    let onSeek: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard !envelope.isEmpty else {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: size.height / 2))
                    line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    ctx.stroke(line, with: .color(.white.opacity(0.12)), lineWidth: 1)
                    return
                }
                let barW = size.width / CGFloat(envelope.count)
                let playedX = size.width * progress
                for (i, amp) in envelope.enumerated() {
                    let x = CGFloat(i) * barW
                    let h = max(2, CGFloat(amp) * size.height)
                    let y = (size.height - h) / 2
                    let rect = CGRect(x: x, y: y, width: max(1, barW - 1), height: h)
                    let color: Color = x <= playedX ? Theme.violet : Color.white.opacity(0.14)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                }
                var line = Path()
                line.move(to: CGPoint(x: playedX, y: 0))
                line.addLine(to: CGPoint(x: playedX, y: size.height))
                ctx.stroke(line, with: .color(Theme.cyan.opacity(0.9)), lineWidth: 1.5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let f = min(max(0, value.location.x / geo.size.width), 1)
                        onSeek(f)
                    }
            )
        }
    }
}
