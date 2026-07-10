import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Brief da sessão: modo, idiomas, modelo do coach e o CV completo (modo entrevista).
/// O CV entra no system prompt do coach — ele sugere histórias/fatos REAIS teus.
struct BriefEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var importingCV = false
    @State private var importError: String?

    private let langs = ["pt-BR", "en-US", "es-ES", "fr-FR", "de-DE", "it-IT"]

    var body: some View {
        @Bindable var app = app

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Brief da sessão")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Concluir") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(14)

            Divider()

            Form {
                Section {
                    Picker("Modo", selection: $app.brief.mode) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Idioma da conversa", selection: $app.brief.conversationLang) {
                        ForEach(langs, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Seu idioma nativo", selection: $app.brief.nativeLang) {
                        ForEach(langs, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Modelo do live coach", selection: $app.coachModel) {
                        ForEach(CoachModel.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Transcrição (STT)", selection: $app.sttSource) {
                        ForEach(SttSource.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Objetivo") {
                    TextField("O que você quer desta conversa", text: $app.brief.goal, axis: .vertical)
                        .lineLimit(2...3)
                }

                Section("Contexto") {
                    TextField("Vaga, empresa, o que destacar/evitar…", text: $app.brief.details, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    TextEditor(text: Binding(
                        get: { app.brief.cv ?? "" },
                        set: { app.brief.cv = $0.isEmpty ? nil : $0 }
                    ))
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 160)

                    HStack {
                        Button {
                            importingCV = true
                        } label: {
                            Label("Importar arquivo (.pdf/.md/.txt)", systemImage: "doc.badge.arrow.up")
                        }
                        Spacer()
                        Text("\((app.brief.cv ?? "").count) caracteres")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if let importError {
                        Text(importError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Currículo / CV (modo entrevista)")
                } footer: {
                    Text("Cole ou importe o CV completo. O coach usa isso pra apontar as SUAS histórias reais nas respostas.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 560, height: 640)
        .fileImporter(
            isPresented: $importingCV,
            allowedContentTypes: [.pdf, .plainText, UTType(filenameExtension: "md") ?? .plainText]
        ) { result in
            importError = nil
            switch result {
            case .success(let url):
                importCV(from: url)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
    }

    private func importCV(from url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        let text: String?
        if url.pathExtension.lowercased() == "pdf" {
            text = PDFDocument(url: url)?.string
        } else {
            text = try? String(contentsOf: url, encoding: .utf8)
        }

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            importError = "Não consegui extrair texto de \(url.lastPathComponent)."
            return
        }
        app.brief.cv = String(text.prefix(12_000))
    }
}
