import SwiftUI

struct SavedHistoryCoachCard: View {
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

struct SavedHistoryLine: View {
    let line: TranscriptLine
    let foreign: Bool
    var active = false
    var onTap: (() -> Void)?
    private var color: Color { line.speaker == .self ? Theme.cyan : Theme.violet }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if onTap != nil {
                Image(systemName: active ? "speaker.wave.2.fill" : "play.fill")
                    .font(.system(size: 8)).foregroundStyle(active ? Theme.mint : .clear).frame(width: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(line.speaker.label.uppercased())
                    .font(.system(size: 8.5, weight: .heavy)).foregroundStyle(color)
                Text(line.text).font(.system(size: 13)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if foreign, let translation = line.translation, !translation.isEmpty {
                    Text(translation).font(.system(size: 12)).foregroundStyle(.secondary)
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
