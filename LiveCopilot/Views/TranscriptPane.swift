import SwiftUI

struct TranscriptPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Transcrição ao vivo", systemImage: "waveform")

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(app.transcript) { line in
                            TranscriptRow(line: line, foreign: app.brief.isForeign)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
                .onChange(of: app.transcript.count) { _, _ in
                    if let last = app.transcript.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: app.transcript.last?.text) { _, _ in
                    if let last = app.transcript.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct TranscriptRow: View {
    let line: TranscriptLine
    let foreign: Bool

    private var color: Color {
        line.speaker == .self ? .blue : .purple
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(line.speaker.label.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color, in: Capsule())
                if !line.isFinal {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
            }

            Text(line.text)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(line.isFinal ? .primary : .secondary)
                .italic(!line.isFinal)
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if foreign {
                if let translation = line.translation, !translation.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 13))
                            .foregroundStyle(color.opacity(0.8))
                        Text(translation)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .lineSpacing(1)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if line.isFinal {
                    // Placeholder enquanto a tradução chega (garante que sempre aparece).
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 13))
                            .foregroundStyle(color.opacity(0.4))
                        Text("traduzindo…")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PaneHeader: View {
    let title: String
    let systemImage: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.system(size: 15, weight: .bold))
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.4))
    }
}
