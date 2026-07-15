import SwiftUI

struct VoiceMemoImportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var items: [VoiceMemoItem] = []
    @State private var loading = true
    @State private var search = ""

    private var filteredItems: [VoiceMemoItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Voice Memos")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Importação somente leitura; o original não é alterado.")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fechar", action: dismiss.callAsFunction).buttonStyle(.bordered)
            }
            .padding(16)
            Divider()

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Buscar gravações", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 11).frame(height: 34)
            .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.divider))
            .padding(14)

            if loading {
                Spacer()
                ProgressView("Lendo Voice Memos…")
                Spacer()
            } else if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredItems) { item in
                            memoRow(item)
                        }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 14)
                }
            }
        }
        .frame(width: 560, height: 520)
        .background(Theme.background)
        .task { items = await VoiceMemoLibrary.discover(); loading = false }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "mic.slash")
                .font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Nenhuma gravação acessível")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text("O macOS não oferece uma API pública do Voice Memos. Se a biblioteca não estiver acessível, exporte ou arraste a gravação e selecione o arquivo M4A.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
            Button("Selecionar arquivo…") {
                dismiss()
                DispatchQueue.main.async { app.chooseAudioFiles() }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private func memoRow(_ item: VoiceMemoItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .foregroundStyle(Theme.violet)
                .frame(width: 30, height: 30)
                .background(Theme.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                HStack(spacing: 8) {
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if item.duration > 0 { Text(SessionArchive.clock(item.duration)) }
                }
                .font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Importar") {
                dismiss()
                Task { await app.importVoiceMemo(item) }
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(10)
        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.divider))
    }
}
