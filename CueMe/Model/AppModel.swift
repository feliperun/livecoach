import Foundation
import Observation
import AppKit
import Translation

/// Estado observável da UI. Só leitura pela view; as raias empurram atualizações
/// pelo `@MainActor`. Comandos delegam ao `SessionCoordinator`.
@MainActor
@Observable
final class AppModel {
    var transcript: [TranscriptLine] = []
    var summaryBullets: [String] = []
    var coachCards: [CoachCard] = []
    var sessionState: SessionState = .idle

    var brief: SessionBrief {
        didSet { BriefStore.save(brief) }
    }

    var sttSource: SttSource = .native
    var coachModel: CoachModel = .deepseekPro {   // default DeepSeek V4 Pro; persiste entre sessões
        didSet { UserDefaults.standard.set(coachModel.rawValue, forKey: Self.coachModelKey) }
    }
    private static let coachModelKey = "coachModel"
    var echoCancellation: Bool = false     // AEC experimental (sem fones); default off
    var trainingMode: Bool = false         // entrevistador por voz (teste e2e + prep solo)
    var recordAudio: Bool = true           // grava o áudio original sincronizado (default ligado)
    var manualInput: String = ""
    var silenceMode: Bool = false          // pausa o coach, mantém transcript
    var backendAvailable: Bool             // Claude Code CLI encontrado?
    var systemCaptureActive: Bool = false  // ScreenCaptureKit capturando o interlocutor?

    // UI compacta
    var pinned: Bool = false {             // janela sempre no topo
        didSet { applyPinned() }
    }
    var showTranscript: Bool = false
    var showSummary: Bool = false
    var showSettings: Bool = false
    var showHistory: Bool = false
    var currentQuestionID: UUID?           // última pergunta/deixa do interlocutor

    // Histórico de sessões.
    var history: [SessionRecord] = []
    private var sessionStartedAt: Date?
    var sessionStartTime: Date? { sessionStartedAt }
    private(set) var currentSessionID: UUID?

    /// Tradução nativa on-device: config observável aqui, loop no pipe (Sendable).
    /// A RootView pluga `.translationTask(translationConfig)`.
    var translationConfig: TranslationSession.Configuration?
    @ObservationIgnored nonisolated let translationPipe = TranslationPipe()

    private var coordinator: SessionCoordinator?

    init() {
        self.brief = BriefStore.load()
        if let raw = UserDefaults.standard.string(forKey: Self.coachModelKey),
           let saved = CoachModel(rawValue: raw) {
            self.coachModel = saved
        }
        self.backendAvailable = ClaudeClient().isAvailable || DeepSeekCredential.isConfigured
        translationPipe.onResult = { [weak self] id, text in
            Task { @MainActor in self?.setTranslation(lineID: id, translation: text) }
        }
        self.history = SessionStore.loadAll()
    }

    // MARK: - Tradução

    func configureTranslation(source: String, target: String) {
        translationPipe.reset()
        translationConfig = .init(
            source: Locale.Language(identifier: SessionBrief.baseCode(source)),
            target: Locale.Language(identifier: SessionBrief.baseCode(target))
        )
    }

    func stopTranslation() {
        translationConfig = nil
        translationPipe.finish()
    }

    func enqueueTranslation(id: UUID, text: String) {
        translationPipe.enqueue(id: id, text: text)
    }

    var isRunning: Bool {
        if case .running = sessionState { return true }
        return false
    }

    var statusText: String {
        switch sessionState {
        case .idle: return "Pronto"
        case .preparing: return "Preparando…"
        case .running: return "Ao vivo"
        case .paused: return "Pausado"
        case .error(let m): return "Erro: \(m)"
        }
    }

    /// Última pergunta destacada no topo (deriva do transcript pra receber tradução).
    var currentQuestion: TranscriptLine? {
        guard let id = currentQuestionID else { return nil }
        return transcript.first(where: { $0.id == id })
    }

    // MARK: - Comandos

    func start() {
        guard !isRunning, sessionState != .preparing else { return }
        // Sessão nova: limpa os painéis (o snapshot da anterior já foi salvo no stop).
        transcript = []
        coachCards = []
        summaryBullets = []
        currentQuestionID = nil
        sessionStartedAt = Date()
        currentSessionID = UUID()
        let coord = SessionCoordinator(app: self)
        self.coordinator = coord
        Task { await coord.start() }
    }

    func stop() {
        let coord = coordinator
        coordinator = nil
        sessionState = .idle
        Task { @MainActor in
            let duration = await coord?.stop()
            self.saveSessionRecord(audioDuration: duration)
        }
    }

    /// Encerra a sessão atual (salva no histórico) e começa uma nova, limpa.
    /// Um clique só: sem precisar Parar → Iniciar.
    func newSession() {
        guard isRunning || sessionState == .preparing else {
            start()   // ocioso: start() já limpa os painéis
            return
        }
        let coord = coordinator
        coordinator = nil
        sessionState = .idle
        Task { @MainActor in
            let duration = await coord?.stop()
            self.saveSessionRecord(audioDuration: duration)
            self.start()
        }
    }

    /// Salva a sessão atual no histórico (se teve conteúdo).
    private func saveSessionRecord(audioDuration: TimeInterval?) {
        defer { sessionStartedAt = nil; currentSessionID = nil }
        guard let startedAt = sessionStartedAt,
              !transcript.isEmpty || !coachCards.isEmpty else { return }
        let record = SessionRecord(
            id: currentSessionID ?? UUID(),
            startedAt: startedAt,
            mode: brief.mode,
            training: trainingMode,
            conversationLang: brief.conversationLang,
            nativeLang: brief.nativeLang,
            goal: brief.goal,
            transcript: transcript,
            coachCards: coachCards.map { var c = $0; c.isStreaming = false; return c },
            summaryBullets: summaryBullets,
            hasAudio: audioDuration != nil,
            audioDuration: audioDuration ?? 0
        )
        SessionStore.save(record)
        history.insert(record, at: 0)
    }

    func deleteHistory(_ id: UUID) {
        SessionStore.delete(id)
        history.removeAll { $0.id == id }
    }

    func ask() {
        let text = manualInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        manualInput = ""
        Task { [coordinator] in
            await coordinator?.ask(text)
        }
    }

    func toggleSilence() {
        silenceMode.toggle()
    }

    func refreshBackendStatus() {
        backendAvailable = ClaudeClient().isAvailable || DeepSeekCredential.isConfigured
    }

    /// Abre o painel de Gravação de Tela (pro áudio do interlocutor).
    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    private func applyPinned() {
        for window in NSApplication.shared.windows where window.isVisible {
            window.level = pinned ? .floating : .normal
        }
    }

    // MARK: - Aplicação de eventos (chamado pelo coordinator, já no MainActor)

    /// Insere/atualiza a linha e devolve o id da linha afetada.
    @discardableResult
    func upsertLine(_ event: TranscriptEvent) -> UUID {
        let id: UUID
        if let idx = transcript.firstIndex(where: { !$0.isFinal && $0.speaker == event.speaker }) {
            transcript[idx].text = event.text
            transcript[idx].isFinal = event.isFinal
            id = transcript[idx].id
        } else {
            let line = TranscriptLine(
                speaker: event.speaker,
                text: event.text,
                isFinal: event.isFinal
            )
            transcript.append(line)
            id = line.id
        }
        if transcript.count > 400 {
            transcript.removeFirst(transcript.count - 400)
        }
        return id
    }

    /// Remove uma linha (dedup de eco: fala do interlocutor que vazou pro mic).
    func removeLine(id: UUID) {
        transcript.removeAll { $0.id == id }
        if currentQuestionID == id { currentQuestionID = nil }
    }

    /// Descarta a linha parcial pendente de um locutor (eco detectado no final).
    func dropUnfinalized(speaker: Speaker) {
        if let idx = transcript.lastIndex(where: { !$0.isFinal && $0.speaker == speaker }) {
            transcript.remove(at: idx)
        }
    }

    func setTranslation(lineID: UUID, translation: String) {
        guard let idx = transcript.firstIndex(where: { $0.id == lineID }) else { return }
        transcript[idx].translation = translation
    }

    func upsertCoach(_ card: CoachCard) {
        if let idx = coachCards.firstIndex(where: { $0.id == card.id }) {
            coachCards[idx] = card
        } else {
            coachCards.append(card)
        }
        if coachCards.count > 30 {
            coachCards.removeFirst(coachCards.count - 30)
        }
    }

    /// Remove cards sem conteúdo (ex.: placeholder que virou "NADA").
    func pruneEmptyCoachCards() {
        coachCards.removeAll { $0.guidePT.isEmpty && ($0.sayConversation?.isEmpty ?? true) && $0.sayNative.isEmpty }
    }
}
