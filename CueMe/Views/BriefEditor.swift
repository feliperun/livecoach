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
    @State private var deepseekKey = ""
    @State private var deepseekBaseURL = ""
    @State private var deepgramKey = ""
    @State private var selectedProfileID: UUID?
    @State private var profileName = ""
    @State private var showingContexts = false

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
                Section("Perfil rápido") {
                    Picker("Perfil", selection: $selectedProfileID) {
                        Text("Configuração atual").tag(UUID?.none)
                        ForEach(app.profiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    .onChange(of: selectedProfileID) { _, id in
                        if let id { app.applyProfile(id) }
                    }
                    HStack {
                        TextField("Nome do perfil", text: $profileName)
                        Button("Salvar") {
                            selectedProfileID = app.saveProfile(named: profileName)
                            profileName = ""
                        }
                        .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let selectedProfileID {
                            Button(role: .destructive) {
                                app.deleteProfile(selectedProfileID)
                                self.selectedProfileID = nil
                            } label: { Image(systemName: "trash") }
                            .help("Apagar perfil")
                        }
                    }
                }

                Section {
                    Picker("Projeto", selection: $app.activeProjectID) {
                        Text("Sem projeto").tag(UUID?.none)
                        ForEach(app.projects.filter { !$0.archived }) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
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
                    Picker("Modelo da ata", selection: $app.summaryModel) {
                        ForEach(CoachModel.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Transcrição (STT)", selection: $app.sttSource) {
                        ForEach(SttSource.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle(isOn: $app.echoCancellation) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Cancelamento de eco (experimental)")
                            Text("Sem fones: tira a voz do interlocutor do seu mic.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(app.isRunning)

                    Toggle(isOn: $app.trainingMode) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Modo treino (entrevistador por voz)")
                            Text("Um entrevistador lê a pauta + CV e faz perguntas por voz, adaptando às suas respostas.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(app.isRunning || app.brief.mode.isPassive)

                    Toggle(isOn: $app.recordAudio) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Gravar áudio da sessão")
                            Text("Grava os dois lados sincronizados com a transcrição, pra reouvir depois.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(app.isRunning)
                }

                Section {
                    HStack {
                        Label(
                            app.selectedMeetingContexts.isEmpty
                                ? "Nenhum contexto ativo"
                                : "\(app.selectedMeetingContexts.count) contexto(s) ativo(s)",
                            systemImage: "books.vertical"
                        )
                        Spacer()
                        Button("Gerenciar…") { showingContexts = true }
                            .disabled(app.isSessionBusy)
                    }
                    Picker("Modelo do glossário", selection: $app.glossaryModel) {
                        ForEach(CoachModel.allCases) { Text($0.label).tag($0) }
                    }
                    HStack {
                        glossaryStatus(app.glossaryGenerationState)
                        Spacer()
                        Button("Gerar agora") {
                            Task { await app.generateContextGlossary() }
                        }
                        .disabled(
                            app.selectedMeetingContexts.isEmpty
                                || app.glossaryGenerationState == .generating
                                || app.isSessionBusy
                        )
                    }
                } header: {
                    Text("Contextos inteligentes")
                } footer: {
                    Text("Ao iniciar com Deepgram, a LLM selecionada gera ou reutiliza até 100 keyterms dentro do limite de 500 tokens. Os contextos selecionados também orientam o coach e a ata.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Image(systemName: "folder")
                        Text(app.archivePath)
                            .font(.system(size: 10.5, design: .monospaced))
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Spacer()
                    }
                    HStack {
                        Button("Escolher pasta…") { app.chooseArchiveRoot() }
                            .disabled(app.isSessionBusy)
                        Button("Mostrar no Finder") { app.revealArchive() }
                    }
                } header: {
                    Text("Arquivo das reuniões")
                } footer: {
                    Text("Cada sessão fica numa pasta com data e hora, com áudio, JSON e uma cópia Markdown.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                if app.coachModel.isDeepSeek || app.summaryModel.isDeepSeek || app.glossaryModel.isDeepSeek {
                    Section {
                        SecureField("API key (sk-…)", text: $deepseekKey)
                            .textContentType(.password)
                            .onChange(of: deepseekKey) { _, new in
                                DeepSeekCredential.setAPIKey(new)
                                app.refreshBackendStatus()
                            }
                        TextField("Endpoint", text: $deepseekBaseURL, prompt: Text(DeepSeekCredential.defaultBaseURL))
                            .onChange(of: deepseekBaseURL) { _, new in
                                DeepSeekCredential.baseURL = new
                            }
                    } header: {
                        Text("DeepSeek")
                    } footer: {
                        Text("A key fica no Keychain. Brief, CV e contextos selecionados são enviados ao endpoint somente para as funções que usam DeepSeek.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if app.sttSource == .deepgram {
                    Section {
                        SecureField("API key", text: $deepgramKey)
                            .textContentType(.password)
                            .onChange(of: deepgramKey) { _, new in
                                DeepgramCredential.setAPIKey(new)
                                app.refreshBackendStatus()
                            }
                        Label(
                            app.deepgramAvailable ? "Chave salva" : "Chave necessária",
                            systemImage: app.deepgramAvailable ? "checkmark.circle.fill" : "key"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(app.deepgramAvailable ? Theme.mint : Theme.amber)
                        TextField("Glossário (separe por vírgulas)", text: Binding(
                            get: { app.vocabulary.keyterms.joined(separator: ", ") },
                            set: { value in
                                var vocabulary = app.vocabulary
                                vocabulary.keyterms = GlossaryTermPolicy.sanitized(value.split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty })
                                app.vocabulary = vocabulary
                            }
                        ), axis: .vertical)
                        .lineLimit(2...4)
                        if !app.vocabulary.replacements.isEmpty {
                            Label(
                                "\(app.vocabulary.replacements.count) correções aprendidas",
                                systemImage: "text.badge.checkmark"
                            )
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Deepgram Nova-3")
                    } footer: {
                        Text("A chave fica no Keychain. O glossário prioriza nomes e termos; correções feitas na transcrição são reaproveitadas nas próximas sessões.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if app.brief.mode.isPassive {
                    Section {
                        Label("Neste modo o coach ao vivo fica desligado. Depois, você ainda pode resumir, extrair ações e perguntar sobre a reunião.", systemImage: "info.circle")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
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
        .sheet(isPresented: $showingContexts) {
            ContextLibraryView()
                .environment(app)
        }
        .onAppear {
            selectedProfileID = app.activeProfileID
            deepseekKey = DeepSeekCredential.apiKey ?? ""
            deepgramKey = DeepgramCredential.apiKey ?? ""
            let stored = DeepSeekCredential.baseURL
            deepseekBaseURL = stored == DeepSeekCredential.defaultBaseURL ? "" : stored
        }
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

    @ViewBuilder
    private func glossaryStatus(_ state: GlossaryGenerationState) -> some View {
        switch state {
        case .idle:
            Label("Será preparado ao iniciar", systemImage: "sparkles")
                .foregroundStyle(.secondary)
        case .generating:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Gerando glossário…")
            }
            .foregroundStyle(Theme.amber)
        case .ready(let count):
            Label("\(count) termos prontos", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.mint)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.amber)
                .lineLimit(2)
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
