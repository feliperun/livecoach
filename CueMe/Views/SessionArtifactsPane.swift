import SwiftUI

struct SessionArtifactsPane: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    if record.artifacts.isEmpty { emptyState }
                    ForEach(record.artifacts.reversed()) { artifact in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(artifact.title).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.violet)
                            Text(artifact.body).font(.system(size: 12.5)).textSelection(.enabled)
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.divider))
                    }
                    if let error = app.postProcessingError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(size: 10.5)).foregroundStyle(Theme.rose)
                    }
                }
                .padding(14)
            }
            composer
        }
    }

    private var composer: some View {
        @Bindable var app = app
        return HStack(spacing: 8) {
            TextField("Pergunte ou gere algo…", text: $app.postSessionPrompt)
                .textFieldStyle(.plain).font(.system(size: 12)).onSubmit(submit)
            Button(action: submit) { Image(systemName: "arrow.up.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(Theme.brand)
                .disabled(app.postSessionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 20, weight: .light)).foregroundStyle(Theme.violet.opacity(0.7))
            Text("Pergunte sobre esta reunião").font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
    }

    private func submit() {
        app.askAboutSession(record.id)
    }
}
