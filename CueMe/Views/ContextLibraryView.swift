import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContextLibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID?
    @State private var importingContext = false
    @State private var importError: String?

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Contextos")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Fontes reutilizáveis para glossário, coach e ata")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Concluir") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 8) {
                    if app.contexts.isEmpty {
                        ContentUnavailableView(
                            "Nenhum contexto",
                            systemImage: "books.vertical",
                            description: Text("Crie um para produto, cliente, empresa ou projeto.")
                        )
                    } else {
                        List(selection: $editingID) {
                            ForEach(app.contexts) { context in
                                HStack(spacing: 8) {
                                    Toggle("", isOn: Binding(
                                        get: { app.selectedContextIDs.contains(context.id) },
                                        set: { _ in app.toggleMeetingContext(context.id) }
                                    ))
                                    .labelsHidden()
                                    Text(context.name.isEmpty ? "Sem nome" : context.name)
                                        .lineLimit(1)
                                }
                                .tag(context.id)
                            }
                        }
                        .listStyle(.sidebar)
                    }

                    HStack {
                        Button {
                            editingID = app.addMeetingContext()
                        } label: {
                            Label("Novo", systemImage: "plus")
                        }
                        Spacer()
                        if let editingID {
                            Button(role: .destructive) {
                                app.deleteMeetingContext(editingID)
                                self.editingID = app.contexts.first?.id
                            } label: {
                                Image(systemName: "trash")
                            }
                            .help("Apagar contexto")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .frame(width: 220)

                Divider()

                Group {
                    if let index = app.contexts.firstIndex(where: { $0.id == editingID }) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Nome do contexto", text: $app.contexts[index].name)
                                .font(.system(size: 16, weight: .semibold))
                                .textFieldStyle(.plain)
                            Divider()
                            TextEditor(text: $app.contexts[index].content)
                                .font(.system(size: 12.5, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .overlay(alignment: .topLeading) {
                                    if app.contexts[index].content.isEmpty {
                                        Text("Cole nomes, produtos, siglas, tecnologias, pauta ou documentação relevante…")
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(.tertiary)
                                            .padding(.top, 7)
                                            .allowsHitTesting(false)
                                    }
                                }
                            HStack {
                                Button {
                                    importingContext = true
                                } label: {
                                    Label("Importar .pdf/.md/.txt", systemImage: "doc.badge.arrow.up")
                                }
                                Label(
                                    app.selectedContextIDs.contains(app.contexts[index].id) ? "Usado na próxima sessão" : "Inativo",
                                    systemImage: app.selectedContextIDs.contains(app.contexts[index].id) ? "checkmark.circle.fill" : "circle"
                                )
                                .foregroundStyle(app.selectedContextIDs.contains(app.contexts[index].id) ? Theme.mint : .secondary)
                                Spacer()
                                Text("\(app.contexts[index].content.count) caracteres")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 10.5))
                            if let importError {
                                Text(importError)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(16)
                    } else {
                        ContentUnavailableView("Selecione um contexto", systemImage: "doc.text.magnifyingglass")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas.opacity(0.35))
            }
        }
        .frame(width: 720, height: 480)
        .onAppear { editingID = editingID ?? app.contexts.first?.id }
        .fileImporter(
            isPresented: $importingContext,
            allowedContentTypes: [.pdf, .plainText, UTType(filenameExtension: "md") ?? .plainText]
        ) { result in
            importError = nil
            switch result {
            case .success(let url): importContext(from: url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
    }

    private func importContext(from url: URL) {
        guard let editingID, let index = app.contexts.firstIndex(where: { $0.id == editingID }) else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        let text = url.pathExtension.lowercased() == "pdf"
            ? PDFDocument(url: url)?.string
            : try? String(contentsOf: url, encoding: .utf8)
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            importError = "Não consegui extrair texto de \(url.lastPathComponent)."
            return
        }
        app.contexts[index].content = String(text.prefix(40_000))
        if app.contexts[index].name == "Novo contexto" {
            app.contexts[index].name = url.deletingPathExtension().lastPathComponent
        }
    }
}
