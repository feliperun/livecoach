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
    var activeCoachCardID: UUID?
    private var dismissedCoachCardIDs: Set<UUID> = []
    var sessionState: SessionState = .idle

    var brief: SessionBrief {
        didSet { BriefStore.save(brief) }
    }

    var sttSource: SttSource = .native
    var coachModel: CoachModel = .sonnet {        // default keyless; DeepSeek é opt-in
        didSet { UserDefaults.standard.set(coachModel.rawValue, forKey: Self.coachModelKey) }
    }
    private static let coachModelKey = "coachModel"
    var echoCancellation: Bool = false     // AEC experimental (sem fones); default off
    var trainingMode: Bool = false         // entrevistador por voz (teste e2e + prep solo)
    var recordAudio: Bool = true           // grava o áudio original sincronizado (default ligado)
    var manualInput: String = ""
    var silenceMode: Bool = false          // pausa o coach, mantém transcript
    private(set) var claudeAvailable = false
    private(set) var deepSeekAvailable = false
    var coachBackendReady = false
    var coachBackendError: String?
    var summaryBackendError: String?
    var systemCaptureActive: Bool = false  // ScreenCaptureKit capturando o interlocutor?
    var micCaptureState: CaptureChannelState = .waiting
    var systemCaptureState: CaptureChannelState = .waiting
    var micLevel: Float = 0
    var systemLevel: Float = 0

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
        let hasClaude = ClaudeClient().isAvailable
        let hasDeepSeek = DeepSeekCredential.isConfigured
        self.claudeAvailable = hasClaude
        self.deepSeekAvailable = hasDeepSeek

        var selected: CoachModel = .sonnet
        if let raw = UserDefaults.standard.string(forKey: Self.coachModelKey),
           let saved = CoachModel(rawValue: raw) {
            selected = saved
        }
        // Migração segura da v0.5: não deixa um provedor indisponível selecionado
        // quando o outro já está pronto para uso.
        self.coachModel = CoachModel.resolved(
            preferred: selected,
            claudeAvailable: hasClaude,
            deepSeekAvailable: hasDeepSeek
        )
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

    var isSessionBusy: Bool {
        switch sessionState {
        case .preparing, .running, .stopping: return true
        default: return false
        }
    }

    var backendAvailable: Bool {
        coachModel.isDeepSeek ? deepSeekAvailable : claudeAvailable
    }

    var statusText: String {
        switch sessionState {
        case .idle: return "Pronto"
        case .preparing: return "Preparando…"
        case .running: return "Ao vivo"
        case .stopping: return "Salvando…"
        case .paused: return "Pausado"
        case .error(let m): return "Erro: \(m)"
        }
    }

    /// Última pergunta destacada no topo (deriva do transcript pra receber tradução).
    var currentQuestion: TranscriptLine? {
        guard let id = currentQuestionID else { return nil }
        return transcript.first(where: { $0.id == id })
    }

    var activeCoachCard: CoachCard? {
        guard let activeCoachCardID else { return nil }
        return coachCards.first(where: { $0.id == activeCoachCardID })
    }

    // MARK: - Comandos

    func start() {
        guard !isSessionBusy else { return }
        guard brief.mode.isPassive || backendAvailable else {
            sessionState = .error(coachModel.isDeepSeek
                ? "Configure a chave da DeepSeek."
                : "Claude Code CLI não encontrado.")
            showSettings = true
            return
        }
        // Sessão nova: limpa os painéis (o snapshot da anterior já foi salvo no stop).
        transcript = []
        coachCards = []
        activeCoachCardID = nil
        dismissedCoachCardIDs = []
        summaryBullets = []
        currentQuestionID = nil
        showTranscript = false
        showSummary = false
        silenceMode = false
        micCaptureState = .waiting
        systemCaptureState = .waiting
        micLevel = 0
        systemLevel = 0
        systemCaptureActive = false
        coachBackendReady = false
        coachBackendError = nil
        summaryBackendError = nil
        sessionStartedAt = Date()
        currentSessionID = UUID()
        let coord = SessionCoordinator(app: self)
        self.coordinator = coord
        Task { await coord.start() }
    }

    func stop() {
        guard sessionState != .stopping else { return }
        let coord = coordinator
        guard coord != nil else {
            sessionState = .idle
            return
        }
        sessionState = .stopping
        Task { @MainActor in
            let result = await coord?.stop() ?? .empty
            self.saveSessionRecord(stopResult: result)
            self.coordinator = nil
            self.activeCoachCardID = nil
            self.sessionState = .idle
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
        sessionState = .stopping
        Task { @MainActor in
            let result = await coord?.stop() ?? .empty
            self.saveSessionRecord(stopResult: result)
            self.coordinator = nil
            self.sessionState = .idle
            self.start()
        }
    }

    /// Salva a sessão atual no histórico (se teve conteúdo).
    private func saveSessionRecord(stopResult: SessionStopResult) {
        defer { sessionStartedAt = nil; currentSessionID = nil }
        guard let startedAt = sessionStartedAt,
              !transcript.isEmpty || !coachCards.isEmpty else { return }
        let record = SessionRecord(
            id: currentSessionID ?? UUID(),
            startedAt: startedAt,
            recordingStartedAt: stopResult.recordingStartedAt,
            mode: brief.mode,
            training: trainingMode,
            conversationLang: brief.conversationLang,
            nativeLang: brief.nativeLang,
            goal: brief.goal,
            transcript: transcript,
            coachCards: coachCards.filter(\.hasContent).map { var c = $0; c.isStreaming = false; return c },
            summaryBullets: summaryBullets,
            hasAudio: stopResult.audioDuration != nil,
            audioDuration: stopResult.audioDuration ?? 0
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
        claudeAvailable = ClaudeClient().isAvailable
        deepSeekAvailable = DeepSeekCredential.isConfigured
    }

    func repairMicrophone() {
        Task { [coordinator] in await coordinator?.repairMicrophone() }
    }

    func repairSystemCapture() {
        Task { [coordinator] in await coordinator?.repairSystemCapture() }
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

    func applyCaptureEvent(_ event: AudioCaptureEvent) {
        switch event {
        case .level(.self, let level): micLevel = level
        case .level(.other, let level): systemLevel = level
        case .state(.self, let state):
            micCaptureState = state
            if state != .active { micLevel = 0 }
        case .state(.other, let state):
            systemCaptureState = state
            systemCaptureActive = state == .active
            if state != .active { systemLevel = 0 }
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
        if !dismissedCoachCardIDs.contains(card.id) {
            activeCoachCardID = card.id
        }
    }

    /// Remove cards sem conteúdo (ex.: placeholder que virou "NADA").
    func pruneEmptyCoachCards() {
        let removed = Set(coachCards.filter { !$0.hasContent }.map(\.id))
        coachCards.removeAll { removed.contains($0.id) }
        dismissedCoachCardIDs.subtract(removed)
        if let activeCoachCardID, removed.contains(activeCoachCardID) {
            self.activeCoachCardID = nil
        }
    }

    /// A dica continua no histórico, mas sai da frente assim que o usuário começa
    /// a responder. Atualizações tardias do mesmo stream não podem reativá-la.
    func dismissActiveCoach() {
        guard let activeCoachCardID else { return }
        dismissedCoachCardIDs.insert(activeCoachCardID)
        self.activeCoachCardID = nil
    }
}
