import Foundation
import Observation
import AppKit
import Translation
import Sparkle

/// Estado observável da UI. Só leitura pela view; as raias empurram atualizações
/// pelo `@MainActor`. Comandos delegam ao `SessionCoordinator`.
@MainActor
@Observable
final class AppModel {
    var transcript: [TranscriptLine] = []
    var summaryBullets: [String] = []
    var minutes: MeetingMinutes = .empty
    var meetingReview: MeetingReview = .empty
    var coachCards: [CoachCard] = []
    var diagnostics = SessionDiagnostics()
    var runtimeHealth: RuntimeHealth = .healthy
    @ObservationIgnored private var stickyRuntimeHealth: RuntimeHealth?
    var coachFeedback: [UUID: CoachFeedback] = [:]
    var activeCoachCardID: UUID?
    private var dismissedCoachCardIDs: Set<UUID> = []
    private var pinnedCoachCardIDs: Set<UUID> = []
    var conversationStyle: ConversationStyle = .interview
    var sessionState: SessionState = .idle

    var brief: SessionBrief {
        didSet {
            BriefStore.save(brief)
            if brief != oldValue { invalidateContextGlossary() }
        }
    }
    var profiles: [BriefProfile] = []
    var activeProfileID: UUID?
    var contexts: [MeetingContext] = [] {
        didSet {
            MeetingContextStore.save(contexts)
            invalidateContextGlossary()
        }
    }
    var selectedContextIDs: Set<UUID> = [] {
        didSet {
            MeetingContextStore.saveSelection(selectedContextIDs)
            invalidateContextGlossary()
        }
    }
    var generatedContextKeyterms: [String] = []
    var glossaryGenerationState: GlossaryGenerationState = .idle

    var sttSource: SttSource = .native {
        didSet { UserDefaults.standard.set(sttSource.rawValue, forKey: Self.sttSourceKey) }
    }
    var coachModel: CoachModel = .sonnet {        // default keyless; DeepSeek é opt-in
        didSet {
            UserDefaults.standard.set(coachModel.rawValue, forKey: Self.coachModelKey)
            guard coachModel != oldValue, isRunning else { return }
            Task { [coordinator, coachModel] in await coordinator?.switchCoachModel(to: coachModel) }
        }
    }
    var summaryModel: CoachModel = .opus {
        didSet {
            UserDefaults.standard.set(summaryModel.rawValue, forKey: Self.summaryModelKey)
            guard summaryModel != oldValue, isRunning else { return }
            Task { [coordinator, summaryModel] in await coordinator?.switchSummaryModel(to: summaryModel) }
        }
    }
    var glossaryModel: CoachModel = .sonnet {
        didSet {
            UserDefaults.standard.set(glossaryModel.rawValue, forKey: Self.glossaryModelKey)
            if glossaryModel != oldValue { invalidateContextGlossary() }
        }
    }
    private static let coachModelKey = "coachModel"
    private static let summaryModelKey = "summaryModel"
    private static let glossaryModelKey = "glossaryModel"
    private static let sttSourceKey = "sttSource"
    private static let themePreferenceKey = "themePreference"
    private static let usePersonalMemoryInCoachKey = "usePersonalMemoryInCoach"
    var themePreference: AppThemePreference = .system {
        didSet { UserDefaults.standard.set(themePreference.rawValue, forKey: Self.themePreferenceKey) }
    }
    var usePersonalMemoryInCoach = true {
        didSet {
            UserDefaults.standard.set(usePersonalMemoryInCoach, forKey: Self.usePersonalMemoryInCoachKey)
        }
    }
    var echoCancellation: Bool = false     // AEC experimental (sem fones); default off
    var trainingMode: Bool = false         // entrevistador por voz (teste e2e + prep solo)
    var recordAudio: Bool = true           // grava o áudio original sincronizado (default ligado)
    var manualInput: String = ""
    var silenceMode: Bool = false          // pausa o coach, mantém transcript
    private(set) var claudeAvailable = false
    private(set) var deepSeekAvailable = false
    private(set) var deepgramAvailable = false
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
    var showPreflight: Bool = false
    var preflight: [PreflightCheck: PreflightStatus] = Dictionary(
        uniqueKeysWithValues: PreflightCheck.allCases.map { ($0, .idle) }
    )
    var preflightRunning = false
    var permissionDiagnosis: PermissionDiagnosis?
    var currentQuestionID: UUID?           // última pergunta/deixa do interlocutor

    // Histórico de sessões e índice local pré-normalizado para busca instantânea.
    @ObservationIgnored private var knowledgeIndex = SessionKnowledgeIndex()
    @ObservationIgnored private let semanticMemoryIndex = SemanticMemoryIndex.shared
    var history: [SessionRecord] = [] {
        didSet { knowledgeIndex.rebuild(history) }
    }
    var projects: [KnowledgeProject] = []
    var people: [KnowledgePerson] = []
    var activeProjectID: UUID?
    var libraryProjectFilterID: UUID?
    var libraryLabelFilter: String?
    var selectedSessionID: UUID?
    var sidebarCollapsed = false
    var historySearch = ""
    var historyDateFilter: HistoryDateFilter = .all
    var historyTypeFilter: HistoryTypeFilter = .all
    var audioImportStatus: AudioImportStatus?
    var sessionNotes: [SessionNote] = []
    var sessionTakeaways: [SessionTakeaway] = []
    var sessionArtifacts: [SessionArtifact] = []
    var participantNames: [Speaker: String] = [.self: "Você", .other: "Interlocutor"]
    var vocabulary: CustomVocabulary = .init() {
        didSet { CustomVocabularyStore.save(vocabulary) }
    }
    var noteDraft = ""
    var postSessionPrompt = ""
    var postProcessingSessionID: UUID?
    var postProcessingError: String?
    var globalMemoryAnswer: String?
    var globalMemoryAnswering = false
    private var sessionStartedAt: Date?
    var sessionStartTime: Date? { sessionStartedAt }
    private(set) var currentSessionID: UUID?

    /// Tradução nativa on-device: config observável aqui, loop no pipe (Sendable).
    /// A RootView pluga `.translationTask(translationConfig)`.
    var translationConfig: TranslationSession.Configuration?
    @ObservationIgnored nonisolated let translationPipe = TranslationPipe()
    @ObservationIgnored private let updater = SPUStandardUpdaterController(
        startingUpdater: ProcessInfo.processInfo.environment["CUEME_UI_TESTING"] != "1",
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private var coordinator: SessionCoordinator?

    init() {
        self.brief = BriefStore.load()
        if ProcessInfo.processInfo.environment["CUEME_UI_TESTING"] == "1" {
            self.brief.mode = .meeting
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("CueMeUITests-archive", isDirectory: true)
            try? FileManager.default.removeItem(at: root)
            SessionStore.rootOverride = root
        }
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["CUEME_UI_TESTING"] == "1"
        let hasClaude = ClaudeClient().isAvailable
        // An ad-hoc XCTest host has a different Keychain identity and macOS may
        // block waiting for an access dialog before the test bundle is loaded.
        let hasDeepSeek = isTesting ? false : DeepSeekCredential.isConfigured
        let hasDeepgram = isTesting ? false : DeepgramCredential.isConfigured
        self.claudeAvailable = hasClaude
        self.deepSeekAvailable = hasDeepSeek
        self.deepgramAvailable = hasDeepgram

        if !isTesting,
           let raw = UserDefaults.standard.string(forKey: Self.sttSourceKey),
           let saved = SttSource(rawValue: raw) {
            self.sttSource = saved
        }
        if let raw = UserDefaults.standard.string(forKey: Self.themePreferenceKey),
           let saved = AppThemePreference(rawValue: raw) {
            self.themePreference = saved
        }
        if UserDefaults.standard.object(forKey: Self.usePersonalMemoryInCoachKey) != nil {
            self.usePersonalMemoryInCoach = UserDefaults.standard.bool(forKey: Self.usePersonalMemoryInCoachKey)
        }

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
        let defaultSummary = CoachModel.defaultSummaryModel(for: self.coachModel)
        let savedSummary = UserDefaults.standard.string(forKey: Self.summaryModelKey)
            .flatMap(CoachModel.init(rawValue:)) ?? defaultSummary
        self.summaryModel = CoachModel.resolved(
            preferred: savedSummary,
            claudeAvailable: hasClaude,
            deepSeekAvailable: hasDeepSeek
        )
        let savedGlossary = UserDefaults.standard.string(forKey: Self.glossaryModelKey)
            .flatMap(CoachModel.init(rawValue:)) ?? self.summaryModel
        self.glossaryModel = CoachModel.resolved(
            preferred: savedGlossary,
            claudeAvailable: hasClaude,
            deepSeekAvailable: hasDeepSeek
        )
        self.vocabulary = CustomVocabularyStore.load()
        translationPipe.onResult = { [weak self] id, text in
            Task { @MainActor in self?.setTranslation(lineID: id, translation: text) }
        }
        let entities = KnowledgeEntityStore.load()
        let fileProjects = ProjectWorkspaceStore.loadAll(merging: entities.projects)
        self.projects = fileProjects
        self.people = entities.people
        let loadedHistory = SessionStore.loadAll()
        self.history = isTesting
            ? loadedHistory
            : SessionStore.migrateToWorkspace(loadedHistory, projects: fileProjects)
        self.knowledgeIndex.rebuild(history)
        if !isTesting { try? KnowledgeEntityStore.save(projects: fileProjects, people: entities.people) }
        if ProcessInfo.processInfo.environment["CUEME_UI_TESTING"] == "1" {
            let fixture = UITestFixtures.memory
            self.history = fixture.records
            self.projects = fixture.projects
            self.people = fixture.people
            self.knowledgeIndex.rebuild(history)
        }
        self.profiles = BriefProfileStore.load()
        self.contexts = MeetingContextStore.load()
        let availableIDs = Set(contexts.map(\.id))
        self.selectedContextIDs = MeetingContextStore.loadSelection().intersection(availableIDs)
        if let cache = MeetingContextStore.loadCache(),
           cache.signature == ContextGlossaryRequest.signature(
               contexts: contexts.filter { selectedContextIDs.contains($0.id) },
               brief: brief,
               model: glossaryModel
           ) {
            self.generatedContextKeyterms = cache.terms
            self.glossaryGenerationState = .ready(cache.terms.count)
        }
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
        case .preparing:
            return glossaryGenerationState == .generating ? "Criando glossário…" : "Preparando…"
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

    var historySearchResults: [SessionSearchResult] {
        let scopedHistory = history.filter { record in
            (libraryProjectFilterID == nil || record.projectID == libraryProjectFilterID)
                && (libraryLabelFilter == nil || record.labels.contains(libraryLabelFilter ?? ""))
        }
        let hybrid = semanticMemoryIndex.search(
            query: historySearch,
            date: historyDateFilter,
            type: historyTypeFilter,
            records: scopedHistory
        )
        if !hybrid.isEmpty || historySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return hybrid
        }
        return SessionKnowledgeIndex(records: scopedHistory)
            .search(query: historySearch, date: historyDateFilter, type: historyTypeFilter)
    }

    var filteredHistory: [SessionRecord] {
        let records = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
        return historySearchResults.compactMap { records[$0.recordID] }
    }

    func historySnippet(for recordID: UUID) -> String? {
        guard !historySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return historySearchResults.first { $0.recordID == recordID }?.snippet
    }

    // MARK: - Comandos

    func start() {
        if ProcessInfo.processInfo.environment["CUEME_UI_TESTING"] == "1" {
            beginUITestLiveSession()
            return
        }
        guard !isSessionBusy,
              audioImportStatus?.isActive != true,
              glossaryGenerationState != .generating else { return }
        guard sttSource != .deepgram || deepgramAvailable else {
            sessionState = .error("Configure a chave da Deepgram.")
            showSettings = true
            return
        }
        guard brief.mode.isPassive || backendAvailable else {
            sessionState = .error(coachModel.isDeepSeek
                ? "Configure a chave da DeepSeek."
                : "Claude Code CLI não encontrado.")
            showSettings = true
            return
        }
        sessionState = .preparing
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.prepareContextGlossaryForStart()
            guard self.sessionState == .preparing else { return }
            self.beginSession()
        }
    }

    private func beginSession() {
        // Sessão nova: limpa os painéis (o snapshot da anterior já foi salvo no stop).
        transcript = []
        coachCards = []
        activeCoachCardID = nil
        dismissedCoachCardIDs = []
        pinnedCoachCardIDs = []
        summaryBullets = []
        minutes = .empty
        meetingReview = .empty
        conversationStyle = .fallback(for: brief.mode)
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
        diagnostics = .init()
        coachFeedback = [:]
        sessionNotes = []
        sessionTakeaways = []
        sessionArtifacts = []
        participantNames = [.self: "Você", .other: "Interlocutor"]
        noteDraft = ""
        selectedSessionID = nil
        postProcessingError = nil
        resetRuntimeHealth()
        recordDiagnostic(kind: .session, name: "started")
        sessionStartedAt = Date()
        currentSessionID = UUID()
        if let currentSessionID, let sessionStartedAt {
            _ = SessionStore.prepareSession(id: currentSessionID, startedAt: sessionStartedAt)
        }
        let coord = SessionCoordinator(app: self)
        self.coordinator = coord
        Task { await coord.start() }
    }

    func stop() {
        if ProcessInfo.processInfo.environment["CUEME_UI_TESTING"] == "1", sessionStartedAt != nil {
            sessionState = .stopping
            saveSessionRecord(stopResult: .init(audioDuration: 75, recordingStartedAt: sessionStartedAt))
            activeCoachCardID = nil
            sessionState = .idle
            return
        }
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
            await self.consumeExternalAudioInbox()
        }
    }

    private func beginUITestLiveSession() {
        let now = Date()
        let systemCaptureDenied = ProcessInfo.processInfo.environment[
            "CUEME_UI_TEST_SYSTEM_CAPTURE_DENIED"
        ] == "1"
        let questionID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
        let coachID = UUID(uuidString: "60000000-0000-0000-0000-000000000002")!
        transcript = [
            .init(id: questionID, speaker: .other, text: "Como vamos reduzir o risco da entrega?", isFinal: true, ts: now),
            .init(speaker: .self, text: "Vamos entregar em etapas menores.", isFinal: true, ts: now.addingTimeInterval(4))
        ]
        coachCards = [.init(
            id: coachID, guidePT: "Explique mitigação e prazo",
            sayNative: "Vamos dividir a entrega em marcos semanais.",
            keytermsConversation: ["marcos", "risco"], isStreaming: false, ts: now
        )]
        activeCoachCardID = coachID
        minutes = .init(overview: "A equipe discutiu riscos e entregas incrementais.")
        sessionStartedAt = now
        currentSessionID = UUID(uuidString: "60000000-0000-0000-0000-000000000003")!
        sessionState = .running
        micCaptureState = .active
        systemCaptureState = systemCaptureDenied ? .unavailable : .active
        systemCaptureActive = !systemCaptureDenied
        permissionDiagnosis = systemCaptureDenied ? .notGranted : .ready
        micLevel = 0.65
        systemLevel = 0.55
        coachBackendReady = true
        selectedSessionID = nil
        if let currentSessionID { _ = SessionStore.prepareSession(id: currentSessionID, startedAt: now) }
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

    /// Saves the complete session snapshot in both JSON and Markdown.
    private func saveSessionRecord(stopResult: SessionStopResult) {
        defer { sessionStartedAt = nil; currentSessionID = nil }
        guard let startedAt = sessionStartedAt else { return }
        var record = SessionRecord(
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
            minutes: minutes,
            participantNames: participantNames,
            coachModel: coachModel,
            summaryModel: summaryModel,
            vocabulary: sessionVocabulary(),
            hasAudio: stopResult.audioDuration != nil,
            audioDuration: stopResult.audioDuration ?? 0,
            diagnostics: diagnostics,
            coachFeedback: coachFeedback,
            notes: sessionNotes,
            takeaways: sessionTakeaways,
            review: meetingReview,
            artifacts: sessionArtifacts,
            projectID: activeProjectID
        )
        if ProcessInfo.processInfo.environment["CUEME_UI_TESTING"] == "1" {
            record.applyGeneratedTitle("Plano de mitigação da entrega")
        }
        SessionStore.save(record)
        if let project = projects.first(where: { $0.id == activeProjectID }),
           let relocated = SessionStore.relocate(record, to: project) {
            record = relocated
        }
        replaceHistoryRecord(record)
        selectedSessionID = record.id
        if backendAvailable, !record.transcript.isEmpty {
            Task {
                await generateReview(for: record.id)
            }
        }
    }

    func deleteHistory(_ id: UUID) {
        if let record = history.first(where: { $0.id == id }) {
            SessionStore.delete(record)
        } else {
            SessionStore.delete(id)
        }
        history.removeAll { $0.id == id }
        if selectedSessionID == id { selectedSessionID = nil }
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
        deepgramAvailable = DeepgramCredential.isConfigured
    }

    func applyProfile(_ id: UUID) {
        guard !isSessionBusy, let profile = profiles.first(where: { $0.id == id }) else { return }
        activeProfileID = id
        brief = profile.brief
        coachModel = CoachModel.resolved(
            preferred: profile.coachModel,
            claudeAvailable: claudeAvailable,
            deepSeekAvailable: deepSeekAvailable
        )
        summaryModel = CoachModel.resolved(
            preferred: profile.summaryModel ?? CoachModel.defaultSummaryModel(for: coachModel),
            claudeAvailable: claudeAvailable,
            deepSeekAvailable: deepSeekAvailable
        )
        echoCancellation = profile.echoCancellation
        recordAudio = profile.recordAudio
        selectedContextIDs = Set(profile.contextIDs ?? []).intersection(Set(contexts.map(\.id)))
        glossaryModel = CoachModel.resolved(
            preferred: profile.glossaryModel ?? summaryModel,
            claudeAvailable: claudeAvailable,
            deepSeekAvailable: deepSeekAvailable
        )
    }

    @discardableResult
    func saveProfile(named rawName: String) -> UUID? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isSessionBusy else { return nil }
        if let index = profiles.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            profiles[index].brief = brief
            profiles[index].coachModel = coachModel
            profiles[index].summaryModel = summaryModel
            profiles[index].echoCancellation = echoCancellation
            profiles[index].recordAudio = recordAudio
            profiles[index].contextIDs = selectedContextIDs.sorted { $0.uuidString < $1.uuidString }
            profiles[index].glossaryModel = glossaryModel
            activeProfileID = profiles[index].id
        } else {
            let profile = BriefProfile(
                name: name,
                brief: brief,
                coachModel: coachModel,
                summaryModel: summaryModel,
                echoCancellation: echoCancellation,
                recordAudio: recordAudio,
                contextIDs: selectedContextIDs.sorted { $0.uuidString < $1.uuidString },
                glossaryModel: glossaryModel
            )
            profiles.append(profile)
            activeProfileID = profile.id
        }
        profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        BriefProfileStore.save(profiles)
        return activeProfileID
    }

    func deleteProfile(_ id: UUID) {
        guard !isSessionBusy else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = nil }
        BriefProfileStore.save(profiles)
    }

    func checkForUpdates() {
        updater.checkForUpdates(nil)
    }

    func runPreflight() {
        guard !preflightRunning, !isSessionBusy else { return }
        preflightRunning = true
        for check in PreflightCheck.allCases { preflight[check] = .checking }
        Task { @MainActor [weak self] in
            guard let self else { return }
            async let audio: Void = self.runAudioPreflight()
            async let coach: Void = self.runCoachPreflight()
            _ = await (audio, coach)
            self.preflightRunning = false
        }
    }

    private func runAudioPreflight() async {
        let preflightGranted = ScreenCapturePermissionProbe.isGranted
        let permissionGranted = preflightGranted || ScreenCapturePermissionProbe.requestAccess()
        guard await AudioCapture.requestMicPermission() else {
            preflight[.microphone] = .failed
            preflight[.systemAudio] = .failed
            return
        }
        let capture = AudioCapture()
        do {
            try await capture.start(includeSystem: permissionGranted)
        } catch {
            preflight[.microphone] = .failed
            preflight[.systemAudio] = .failed
            return
        }
        let observer = Task { @MainActor [weak self] in
            for await event in capture.events {
                guard let self else { return }
                switch event {
                case .state(.self, .active): self.preflight[.microphone] = .passed
                case .state(.self, .silent), .state(.self, .unavailable): self.preflight[.microphone] = .failed
                case .state(.other, .active): self.preflight[.systemAudio] = .passed
                case .state(.other, .unavailable): self.preflight[.systemAudio] = .failed
                default: break
                }
            }
        }
        try? await Task.sleep(for: .seconds(10))
        capture.finish()
        observer.cancel()
        if preflight[.microphone] == .checking { preflight[.microphone] = .failed }
        if preflight[.systemAudio] == .checking { preflight[.systemAudio] = .failed }
        let captureSucceeded = preflight[.systemAudio] == .passed
        ScreenCapturePermissionProbe.markSuccess(if: captureSucceeded)
        permissionDiagnosis = PermissionDiagnosis.evaluate(
            preflightGranted: preflightGranted,
            captureSucceeded: captureSucceeded,
            currentIdentity: ScreenCapturePermissionProbe.currentIdentity,
            lastSuccessfulIdentity: ScreenCapturePermissionProbe.lastSuccessfulIdentity
        )
    }

    private func runCoachPreflight() async {
        let client = ClaudeClient()
        let session = client.makeCoachSession(
            model: SessionCoordinator.CoachModelPlan.resolve(for: coachModel).live,
            system: Prompts.coachSystem(brief: brief)
        )
        guard let session else {
            preflight[.coach] = .failed
            return
        }
        do {
            try await session.prewarm()
            preflight[.coach] = .passed
        } catch {
            preflight[.coach] = .failed
        }
        await session.shutdown()
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

    func resetScreenRecordingPermission() {
        ScreenCapturePermissionProbe.reset()
        permissionDiagnosis = .notGranted
        openScreenRecordingSettings()
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
            recordDiagnostic(kind: .capture, name: "mic_\(state.diagnosticName)", speaker: .self)
            if state != .active { micLevel = 0 }
        case .state(.other, let state):
            systemCaptureState = state
            recordDiagnostic(kind: .capture, name: "system_\(state.diagnosticName)", speaker: .other)
            systemCaptureActive = state == .active
            if state == .active {
                ScreenCapturePermissionProbe.markSuccess()
                permissionDiagnosis = .ready
            }
            if state != .active { systemLevel = 0 }
        }
        recalculateRuntimeHealth()
    }

    func setRuntimeHealth(_ level: RuntimeHealthLevel, reason: String?, sticky: Bool = false) {
        runtimeHealth = .init(level: level, reason: reason)
        if sticky { stickyRuntimeHealth = runtimeHealth }
    }

    func recalculateRuntimeHealth() {
        if let stickyRuntimeHealth {
            runtimeHealth = stickyRuntimeHealth
            return
        }
        let states = [micCaptureState, systemCaptureState]
        if states.contains(.unavailable) || states.contains(.silent) {
            runtimeHealth = .init(level: .critical, reason: "Um canal está sem áudio")
        } else if states.contains(.recovering) || coachBackendError != nil || summaryBackendError != nil {
            runtimeHealth = .init(level: .degraded, reason: "Recuperando conexão")
        } else if isRunning {
            runtimeHealth = .healthy
        }
    }

    func clearRuntimeHealthIssue(reason: String? = nil) {
        if let reason, stickyRuntimeHealth?.reason != reason { return }
        stickyRuntimeHealth = nil
        recalculateRuntimeHealth()
    }

    func resetRuntimeHealth() {
        stickyRuntimeHealth = nil
        runtimeHealth = .healthy
    }

    func recordDiagnostic(
        kind: DiagnosticEvent.Kind,
        name: String,
        speaker: Speaker? = nil,
        durationMs: Int64? = nil,
        detail: String? = nil
    ) {
        diagnostics.record(.init(
            kind: kind,
            name: name,
            speaker: speaker,
            durationMs: durationMs,
            detail: detail
        ))
    }

    func setCoachFeedback(cardID: UUID, feedback: CoachFeedback) {
        coachFeedback[cardID] = feedback
        recordDiagnostic(kind: .coach, name: feedback == .helpful ? "feedback_helpful" : "feedback_not_helpful")
    }

    // MARK: - Aplicação de eventos (chamado pelo coordinator, já no MainActor)

    /// Insere/atualiza a linha e devolve o id da linha afetada.
    @discardableResult
    func upsertLine(_ event: TranscriptEvent) -> UUID {
        let id: UUID
        if let idx = transcript.firstIndex(where: { !$0.isFinal && $0.speaker == event.speaker }) {
            transcript[idx].text = event.text
            transcript[idx].isFinal = event.isFinal
            if event.isFinal { transcript[idx].sourceTurnID = event.id }
            id = transcript[idx].id
        } else {
            let line = TranscriptLine(
                speaker: event.speaker,
                text: event.text,
                isFinal: event.isFinal,
                sourceTurnID: event.id
            )
            transcript.append(line)
            id = line.id
        }
        // A UI usa LazyVStack; preservar a sessão inteira é mais importante que
        // uma janela curta. 5k linhas cobre reuniões de muitas horas sem crescer
        // sem limite em uma captura acidentalmente deixada aberta.
        if transcript.count > 5_000 {
            transcript.removeFirst(transcript.count - 5_000)
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
        if coachCards.count > 100 {
            coachCards.removeFirst(coachCards.count - 100)
        }
        if !dismissedCoachCardIDs.contains(card.id) {
            let current = activeCoachCard
            let mayAdvance = current == nil || current?.id == card.id
            if mayAdvance { activeCoachCardID = card.id }
        }
    }

    /// Remove cards sem conteúdo (ex.: placeholder que virou "NADA").
    func pruneEmptyCoachCards() {
        let removed = Set(coachCards.filter { !$0.hasContent }.map(\.id))
        coachCards.removeAll { removed.contains($0.id) }
        dismissedCoachCardIDs.subtract(removed)
        pinnedCoachCardIDs.subtract(removed)
        if let activeCoachCardID, removed.contains(activeCoachCardID) {
            self.activeCoachCardID = nil
        }
    }

    /// A dica continua no histórico, mas sai da frente assim que o usuário começa
    /// a responder. Atualizações tardias do mesmo stream não podem reativá-la.
    func dismissActiveCoach() {
        guard let activeCoachCardID else { return }
        dismissedCoachCardIDs.insert(activeCoachCardID)
        pinnedCoachCardIDs.remove(activeCoachCardID)
        self.activeCoachCardID = nextAvailableCoach(after: activeCoachCardID)?.id
    }

    var pendingCoachCount: Int {
        guard let activeCoachCardID,
              let activeIndex = coachCards.firstIndex(where: { $0.id == activeCoachCardID }) else {
            return coachCards.filter { $0.hasContent && !dismissedCoachCardIDs.contains($0.id) }.count
        }
        return coachCards[(activeIndex + 1)...].filter {
            $0.hasContent && !dismissedCoachCardIDs.contains($0.id)
        }.count
    }

    var isActiveCoachPinned: Bool {
        activeCoachCardID.map(pinnedCoachCardIDs.contains) ?? false
    }

    func toggleActiveCoachPin() {
        guard let activeCoachCardID else { return }
        if pinnedCoachCardIDs.contains(activeCoachCardID) {
            pinnedCoachCardIDs.remove(activeCoachCardID)
        } else {
            pinnedCoachCardIDs.insert(activeCoachCardID)
        }
    }

    func useActiveCoach() {
        guard let activeCoachCardID else { return }
        setCoachFeedback(cardID: activeCoachCardID, feedback: .helpful)
        dismissedCoachCardIDs.insert(activeCoachCardID)
        pinnedCoachCardIDs.remove(activeCoachCardID)
        self.activeCoachCardID = nextAvailableCoach(after: activeCoachCardID)?.id
    }

    var activeCoachPosition: (index: Int, count: Int)? {
        let visible = coachCards.filter(\.hasContent)
        guard let activeCoachCardID,
              let index = visible.firstIndex(where: { $0.id == activeCoachCardID }) else { return nil }
        return (index + 1, visible.count)
    }

    func showPreviousCoach() { moveCoach(by: -1) }
    func showNextCoach() { moveCoach(by: 1) }

    private func moveCoach(by offset: Int) {
        let visible = coachCards.filter { $0.hasContent && !dismissedCoachCardIDs.contains($0.id) }
        guard !visible.isEmpty else { return }
        let current = activeCoachCardID.flatMap { id in visible.firstIndex(where: { $0.id == id }) }
            ?? (offset < 0 ? visible.count : -1)
        let target = min(max(current + offset, 0), visible.count - 1)
        activeCoachCardID = visible[target].id
    }

    private func nextAvailableCoach(after id: UUID) -> CoachCard? {
        let visible = coachCards.filter { $0.hasContent && !dismissedCoachCardIDs.contains($0.id) }
        guard let index = coachCards.firstIndex(where: { $0.id == id }) else { return visible.first }
        return visible.first { card in
            guard let candidateIndex = coachCards.firstIndex(where: { $0.id == card.id }) else { return false }
            return candidateIndex > index
        } ?? visible.last
    }

    func setParticipantName(_ rawName: String, for speaker: Speaker) {
        let fallback = speaker.label
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        participantNames[speaker] = name.isEmpty ? fallback : name
        if !name.isEmpty { vocabulary.addKeyterm(name) }
        persistLiveSnapshot()
    }

    func correctTranscript(lineID: UUID, text: String, learn: Bool = true) {
        guard let index = transcript.firstIndex(where: { $0.id == lineID }) else { return }
        let original = transcript[index].text
        transcript[index].applyCorrection(text)
        guard transcript[index].text != original else { return }
        if brief.isForeign {
            transcript[index].translation = nil
            enqueueTranslation(id: lineID, text: transcript[index].text)
        }
        if learn { _ = vocabulary.learnCorrection(from: original, to: transcript[index].text) }
        let turnID = transcript[index].sourceTurnID
        let corrected = transcript[index].text
        Task { [coordinator] in await coordinator?.correctTurn(id: turnID, text: corrected) }
        persistLiveSnapshot()
    }
}

private extension CaptureChannelState {
    var diagnosticName: String {
        switch self {
        case .waiting: return "waiting"
        case .active: return "active"
        case .silent: return "silent"
        case .recovering: return "recovering"
        case .unavailable: return "unavailable"
        }
    }
}
