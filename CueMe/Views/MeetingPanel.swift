import SwiftUI

/// Focused live meeting surface; transport and note capture stay in the bottom bar.
struct MeetingPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Capturando conversa", systemImage: "waveform")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.mint)
                Spacer()
                HStack(spacing: 12) {
                    compactStat("\(app.transcript.filter(\.isFinal).count)", "falas")
                    compactStat("\(app.sessionNotes.count)", "notas")
                }
            }

            if let last = app.transcript.last(where: { $0.isFinal }) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(last.speaker.label.uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(last.speaker == .self ? Theme.cyan : Theme.violet)
                    Text(last.text)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .lineSpacing(3)
                        .lineLimit(5)
                        .contentTransition(.opacity)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.divider))
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Theme.mint)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    Text("Ouvindo…")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("A primeira fala aparece aqui.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
        .animation(.snappy(duration: 0.24), value: app.transcript.last?.id)
    }

    private func compactStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(label).font(.system(size: 8.5)).foregroundStyle(.tertiary)
        }
        .frame(minWidth: 36)
    }
}
