import SwiftUI

extension String {
    /// Renderiza **negrito** vindo do tradutor.
    var markdownAttributed: AttributedString {
        (try? AttributedString(
            markdown: self,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(self)
    }
}

/// Transcript compacto (vive colapsado; abre pra revisar).
struct TranscriptPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(app.transcript) { line in
                        TranscriptRow(line: line, foreign: app.brief.isForeign)
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .onChange(of: app.transcript.count) { _, _ in
                if let last = app.transcript.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

private struct TranscriptRow: View {
    let line: TranscriptLine
    let foreign: Bool

    private var color: Color {
        line.speaker == .self ? Theme.cyan : Theme.violet
    }

    private var isQuestion: Bool {
        line.text.contains("?")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(line.speaker.label.uppercased())
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(color)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
                if isQuestion {
                    Text("❓").font(.system(size: 10))
                }
                if !line.isFinal {
                    Text("…").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            Text(line.text)
                .font(.system(size: 14, weight: isQuestion ? .semibold : .regular))
                .foregroundStyle(line.isFinal ? .primary : .secondary)
                .italic(!line.isFinal)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if foreign, line.isFinal {
                if let translation = line.translation, !translation.isEmpty {
                    Text(translation.markdownAttributed)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("traduzindo…")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isQuestion ? color.opacity(0.07) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
