import SwiftUI

/// Glanceable strip that can sit immediately below the webcam. No transcript,
/// controls, or paragraphs: one prompt and one actionable visual cue.
struct CameraRailView: View {
    @Environment(AppModel.self) private var app

    private var phrase: String? {
        guard let card = app.activeCoachCard else { return nil }
        return card.sayConversation ?? (card.sayNative.isEmpty ? nil : card.sayNative)
    }

    private var guide: String? {
        guard let value = app.activeCoachCard?.guidePT, !value.isEmpty else { return nil }
        return value
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(app.isRunning ? Theme.mint : Color.secondary)
                .frame(width: 8, height: 8)
            if let phrase {
                Text(phrase)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(2)
            } else if let guide {
                VisualGuide(text: guide)
            } else if let question = app.currentQuestion?.text {
                Text(question)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(app.isRunning ? "OUVINDO" : "PRONTO")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 560, height: 74)
        .background(Theme.background.opacity(0.96))
        .preferredColorScheme(.dark)
    }
}

private struct VisualGuide: View {
    let text: String
    private var steps: [String] { text.components(separatedBy: "→").map { $0.trimmingCharacters(in: .whitespaces) } }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                Text(step)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.mint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.mint.opacity(0.12), in: Capsule())
            }
        }
        .lineLimit(1)
    }
}
