import Foundation
import OSLog

/// Orquestra a sessão ao vivo: captura → STT (por origem) → barramento → raias → UI.
/// Vive no `@MainActor`; o trabalho pesado (rede, áudio, STT) roda em actors/URLSession
/// que suspendem fora da main thread nos `await`.
@MainActor
final class SessionCoordinator {
    private let log = Logger(subsystem: "CueMe", category: "SessionCoordinator")
    private unowned let app: AppModel

    private let bus = TranscriptBus()
    private let client = ClaudeClient()

    // Raias e sessões persistentes (warm), criadas no start() com o brief atual.
    // Tradução saiu da LLM → framework nativo Apple (app.translationPipe). Coach fica livre.
    private var summaryLane = SummaryLane(session: nil)
    private var coachingLane = CoachingLane(live: nil, manual: nil)
    private var sessions: [any CoachSession] = []

    private var capture: AudioCapture?
    private var micStt: (any SttSession)?
    private var systemStt: (any SttSession)?
    private var training: TrainingCoordinator?
    private var recorder: MeetingRecorder?
    private var recordingStartedAt: Date?

    private var tasks: [Task<Void, Never>] = []
    private var liveCoachDebounceTask: Task<Void, Never>?
    private var liveCoachTask: Task<Void, Never>?
    private var manualCoachTask: Task<Void, Never>?
    private var summaryDebounceTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private var pendingLiveCoach: CoachRequest?
    private var pendingManualCoach: CoachRequest?
    private var didAttemptMicRepair = false
    private var speculativeDetectors: [Speaker: SpeculativeTurnDetector] = [:]
    private var speculativeDebounceTasks: [Speaker: Task<Void, Never>] = [:]
    private var speculativeText = ""
    private var summaryPolicy = SummarySchedulePolicy()

    // Dedup de eco (setup alto-falante): a fala do interlocutor sai da caixa e volta
    // pelo mic. Guardamos finais recentes de cada lado e derrubamos duplicatas.
    private var recentSystemFinals: [(text: String, ts: Date)] = []
    private var recentMicFinals: [(lineID: UUID, eventID: UUID, text: String, ts: Date)] = []
    private var partialText: [Speaker: String] = [:]
    private let echoWindow: TimeInterval = 8

    private struct CoachRequest: Sendable {
        let window: [Turn]
        let latest: String
        let manual: Bool
        let speakerCertain: Bool
        let cardID: UUID
        let instantGuide: String?
        let bypassDebounce: Bool
        let triggeredAt: ContinuousClock.Instant
    }

    struct CoachModelPlan: Equatable {
        let live: CoachModel
        let manual: CoachModel

        static func resolve(for selected: CoachModel) -> Self {
            if selected.isDeepSeek {
                return .init(live: .deepseekFlash, manual: selected)
            }
            return .init(live: .sonnet, manual: selected)
        }
    }

    enum SummaryBackendSelection: Equatable {
        case claude(model: String)
        case deepSeek(model: CoachModel)

        static func resolve(for coachModel: CoachModel) -> Self {
            coachModel.isDeepSeek
                ? .deepSeek(model: .deepseekFlash)
                : .claude(model: ClaudeClient.fastModel)
        }
    }

    init(app: AppModel) {
        self.app = app
    }

    // MARK: - Ciclo de vida

    func start() async {
        app.sessionState = .preparing

        guard await AudioCapture.requestMicPermission() else {
            app.sessionState = .error("Permissão de microfone negada.")
            return
        }

        let brief = app.brief

        // Tradução nativa on-device (só quando a conversa é estrangeira).
        if brief.isForeign {
            app.configureTranslation(source: brief.conversationLang, target: brief.nativeLang)
        } else {
            app.stopTranslation()
        }

        // Sessões persistentes do Claude CLI (warm após 1º uso). System prompt e
        // modelo fixos por sessão, derivados do brief. Prewarm paga o cold start já.
        buildBrain(brief: brief)

        // STT por origem: um transcritor para o mic (self), outro para o sistema (other).
        let mic = NativeTranscriber(config: SttConfig(
            speaker: .self,
            localeIdentifier: brief.conversationLang,
            keyterms: brief.keyterms
        ))
        let system = NativeTranscriber(config: SttConfig(
            speaker: .other,
            localeIdentifier: brief.conversationLang,
            keyterms: brief.keyterms
        ))
        self.micStt = mic
        self.systemStt = system

        do {
            try await mic.start()
        } catch {
            await failStart(error.localizedDescription)
            return
        }
        // Sistema é best-effort (permissão de tela / modelo). Não derruba a sessão.
        do { try await system.start() }
        catch { log.error("STT de sistema falhou: \(error.localizedDescription, privacy: .public)") }

        // Consumidores de eventos de cada transcritor.
        tasks.append(consume(events: mic.events))
        tasks.append(consume(events: system.events))

        // Coaching reage ao barramento (fim de turno do interlocutor).
        tasks.append(consumeBusForCoaching())

        // Captura de áudio → roteia para o transcritor da origem.
        let capture = AudioCapture()
        self.capture = capture
        do {
            try await capture.start(
                includeSystem: true,
                echoCancellation: app.echoCancellation,
                captureOwnProcess: app.trainingMode   // capta o TTS do entrevistador como `other`
            )
        } catch {
            await failStart(error.localizedDescription)
            return
        }
        app.systemCaptureActive = capture.isSystemActive
        tasks.append(consumeCaptureEvents(from: capture))
        tasks.append(routeAudio(from: capture))

        // Gravação do áudio original, sincronizada com a transcrição (opt-out).
        if app.recordAudio, let sessionID = app.currentSessionID {
            let rec = MeetingRecorder()
            do {
                recordingStartedAt = try await rec.start(directory: MeetingRecording.directory(for: sessionID))
                self.recorder = rec
            } catch {
                log.error("Falha ao iniciar gravação: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Modo treino: entrevistador por voz (lê pauta + CV, adapta às respostas).
        if app.trainingMode, client.isAvailable {
            let training = TrainingCoordinator(client: client, brief: brief)
            self.training = training
            training.start()
        }

        app.sessionState = .running
        log.info("Sessão iniciada (treino: \(self.app.trainingMode, privacy: .public))")
    }

    /// Para a sessão e devolve duração + relógio real da gravação como uma unidade.
    func stop() async -> SessionStopResult {
        summaryDebounceTask?.cancel()
        summaryDebounceTask = nil
        summaryTask?.cancel()
        summaryTask = nil
        if summaryPolicy.hasUnsummarizedTurns {
            await runSummary(final: true)
        }
        pendingLiveCoach = nil
        pendingManualCoach = nil
        liveCoachDebounceTask?.cancel()
        liveCoachDebounceTask = nil
        liveCoachTask?.cancel()
        liveCoachTask = nil
        manualCoachTask?.cancel()
        manualCoachTask = nil
        for t in tasks { t.cancel() }
        tasks.removeAll()

        training?.stop()
        training = nil
        capture?.finish()
        capture = nil
        await micStt?.finish()
        await systemStt?.finish()
        micStt = nil
        systemStt = nil
        await bus.finish()
        let duration = await recorder?.stop()
        recorder = nil
        let audioStart = recordingStartedAt
        recordingStartedAt = nil

        for s in sessions { await s.shutdown() }
        sessions.removeAll()
        summaryLane = SummaryLane(session: nil)
        coachingLane = CoachingLane(live: nil, manual: nil)
        app.stopTranslation()
        app.systemCaptureActive = false
        app.micCaptureState = .waiting
        app.systemCaptureState = .waiting
        app.pruneEmptyCoachCards()
        partialText.removeAll()
        recentSystemFinals.removeAll()
        recentMicFinals.removeAll()
        speculativeDetectors.removeAll()
        for task in speculativeDebounceTasks.values { task.cancel() }
        speculativeDebounceTasks.removeAll()
        speculativeText = ""
        summaryPolicy = .init()
        app.recordDiagnostic(kind: .session, name: "stopped")
        log.info("Sessão parada")
        return SessionStopResult(audioDuration: duration, recordingStartedAt: audioStart)
    }

    private func failStart(_ message: String) async {
        _ = await stop()
        app.sessionState = .error(message)
    }

    /// Cria as sessões persistentes das raias e as AQUECE. Resumo e coach usam o
    /// provedor escolhido; cada um mantém sua própria sessão para não se bloquearem.
    private func buildBrain(brief: SessionBrief) {
        app.coachBackendReady = false
        app.coachBackendError = nil
        app.summaryBackendError = nil

        // Resumo é útil em qualquer modo (inclusive reunião — notas da conversa).
        // DeepSeek selecionado precisa resumir via DeepSeek: usar Claude aqui fazia
        // a pergunta manual funcionar, mas deixava o resumo permanentemente offline.
        let summarySystem = Prompts.summarySystem(brief: brief)
        let summarySession: (any CoachSession)?
        switch SummaryBackendSelection.resolve(for: app.coachModel) {
        case .claude(let model):
            summarySession = client.makeSession(model: model, system: summarySystem)
        case .deepSeek(let model):
            summarySession = client.makeCoachSession(model: model, system: summarySystem)
        }
        if let summarySession {
            summaryLane = SummaryLane(session: summarySession)
            sessions = [summarySession]
        } else {
            app.summaryBackendError = app.coachModel.isDeepSeek
                ? "DeepSeek não configurada."
                : "Claude CLI não encontrado."
        }

        // Modo reunião é passivo (tema livre) — o coach não se aplica, não gasta sessão.
        guard !brief.mode.isPassive else { return }

        let coachSystem = Prompts.coachSystem(brief: brief)
        let modelPlan = CoachModelPlan.resolve(for: app.coachModel)
        // A conversa ao vivo sempre usa o tier rápido. O modelo profundo escolhido
        // fica reservado para perguntas manuais, onde alguns segundos extras cabem.
        let coachLive = client.makeCoachSession(model: modelPlan.live, system: coachSystem)
        let coachManual = client.makeCoachSession(model: modelPlan.manual, system: coachSystem)

        coachingLane = CoachingLane(live: coachLive, manual: coachManual)
        sessions += [coachLive, coachManual].compactMap { $0 }

        guard let coachLive else {
            app.coachBackendError = app.coachModel.isDeepSeek
                ? "DeepSeek não configurada."
                : "Claude CLI não encontrado."
            return
        }

        // Aquece apenas a raia ao vivo. Erros deixam de ser silenciosos e aparecem
        // de forma compacta na UI; a raia manual continua independente.
        tasks.append(Task { [weak self] in
            do {
                try await coachLive.prewarm()
                guard !Task.isCancelled, let self else { return }
                self.app.coachBackendReady = true
                self.app.coachBackendError = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.app.coachBackendError = error.localizedDescription
                self.log.error("Warm-up do coach falhou: \(error.localizedDescription, privacy: .public)")
            }
        })
    }

    func ask(_ text: String) async {
        await bus.appendManual(text)
        app.upsertLine(TranscriptEvent(speaker: .self, text: "❓ \(text)", isFinal: true, isEndOfTurn: true))
        let window = await bus.window()
        triggerCoach(window: window, latest: text, manual: true)
    }

    // MARK: - Roteamento de áudio

    private func routeAudio(from capture: AudioCapture) -> Task<Void, Never> {
        Task { [weak self] in
            for await chunk in capture.chunks {
                guard let self else { break }
                switch chunk.source {
                case .self:  await self.micStt?.feed(chunk.buffer)
                case .other: await self.systemStt?.feed(chunk.buffer)
                }
                await self.recorder?.ingest(chunk)
            }
        }
    }

    private func consumeCaptureEvents(from capture: AudioCapture) -> Task<Void, Never> {
        Task { [weak self] in
            for await event in capture.events {
                guard let self else { break }
                self.app.applyCaptureEvent(event)
                if case .state(.self, .silent) = event, !self.didAttemptMicRepair {
                    self.didAttemptMicRepair = true
                    self.app.echoCancellation = false
                    do {
                        try capture.restartMicWithoutAEC()
                    } catch {
                        self.log.error("Autorrecuperação do mic falhou: \(error.localizedDescription, privacy: .public)")
                        self.app.micCaptureState = .unavailable
                    }
                }
            }
        }
    }

    func repairMicrophone() async {
        guard let capture else { return }
        app.echoCancellation = false
        do {
            try capture.restartMicWithoutAEC()
            didAttemptMicRepair = true
        } catch {
            log.error("Reabertura manual do mic falhou: \(error.localizedDescription, privacy: .public)")
            app.micCaptureState = .unavailable
        }
    }

    func repairSystemCapture() async {
        await capture?.restartSystemCapture()
    }

    // MARK: - Consumo de eventos de STT

    private func consume(events: AsyncStream<TranscriptEvent>) -> Task<Void, Never> {
        Task { [weak self] in
            for await event in events {
                guard let self else { break }
                if event.isFinal {
                    await self.handleFinal(event)
                } else {
                    self.handlePartial(event)
                }
            }
        }
    }

    /// Os dois STTs publicam parciais em ritmos diferentes. Se o mesmo áudio dos
    /// alto-falantes aparece no mic, removemos o parcial `self` imediatamente —
    /// sem esperar a finalização que causava as linhas duplicadas das imagens.
    private func handlePartial(_ event: TranscriptEvent) {
        partialText[event.speaker] = event.text
        switch event.speaker {
        case .other:
            if let mic = partialText[.self], Self.isEcho(mic, event.text) {
                partialText.removeValue(forKey: .self)
                app.dropUnfinalized(speaker: .self)
            }
            app.upsertLine(event)
            triggerSpeculativeCoachIfNeeded(event)

        case .self:
            let recentSystem = recentSystemFinals.suffix(3).map { $0.text }.joined(separator: " ")
            if let system = partialText[.other], Self.isEcho(event.text, system)
                || Self.isEcho(event.text, recentSystem) {
                partialText.removeValue(forKey: .self)
                app.dropUnfinalized(speaker: .self)
                return
            }
            app.dismissActiveCoach()
            app.upsertLine(event)
            triggerSpeculativeCoachIfNeeded(event)
        }
    }

    private func triggerSpeculativeCoachIfNeeded(_ event: TranscriptEvent) {
        guard !app.silenceMode, !app.brief.mode.isPassive else { return }
        var detector = speculativeDetectors[event.speaker] ?? .init()
        let shouldTrigger = detector.observe(event.text, looksActionable: Self.looksLikeQuestion)
        speculativeDetectors[event.speaker] = detector
        if shouldTrigger {
            issueSpeculativeCoach(text: event.text, speaker: event.speaker)
            return
        }
        guard Self.looksLikeQuestion(event.text),
              event.text.split(separator: " ").count >= 4 else { return }
        let text = event.text
        let speaker = event.speaker
        speculativeDebounceTasks[speaker]?.cancel()
        speculativeDebounceTasks[speaker] = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(240)) }
            catch { return }
            guard let self,
                  self.partialText[speaker] == text,
                  self.speculativeText != SpeculativeTurnDetector.normalize(text) else { return }
            self.issueSpeculativeCoach(text: text, speaker: speaker)
        }
    }

    private func issueSpeculativeCoach(text: String, speaker: Speaker) {
        speculativeText = SpeculativeTurnDetector.normalize(text)
        app.recordDiagnostic(kind: .coach, name: "speculative_trigger", speaker: speaker)
        Task { [weak self] in
            guard let self else { return }
            let window = await self.bus.window()
            self.triggerCoach(
                window: window,
                latest: text,
                manual: false,
                speakerCertain: speaker == .other
            )
        }
    }

    private func handleFinal(_ event: TranscriptEvent) async {
        purgeEchoBuffers()
        partialText.removeValue(forKey: event.speaker)
        speculativeDebounceTasks[event.speaker]?.cancel()
        speculativeDebounceTasks[event.speaker] = nil
        speculativeDetectors[event.speaker]?.finalize()

        switch event.speaker {
        case .other:
            // Registra pra derrubar o eco que chegar pelo mic; remove eco que já chegou.
            recentSystemFinals.append((event.text, Date()))
            if let micPartial = partialText[.self], Self.isEcho(micPartial, event.text) {
                partialText.removeValue(forKey: .self)
                app.dropUnfinalized(speaker: .self)
            }
            let dupes = recentMicFinals.filter { Self.isEcho($0.text, event.text) }
            for dupe in dupes {
                app.removeLine(id: dupe.lineID)
                await bus.removeTurn(id: dupe.eventID)
            }
            let duplicateIDs = Set(dupes.map { $0.eventID })
            recentMicFinals.removeAll { duplicateIDs.contains($0.eventID) }
            await bus.publish(event)
            let lineID = app.upsertLine(event)
            app.currentQuestionID = lineID          // pergunta/deixa mais recente no topo
            if app.brief.isForeign { app.enqueueTranslation(id: lineID, text: event.text) }

        case .self:
            // Eco da caixa de som? (interlocutor já transcrito pelo stream de sistema)
            let systemWindow = recentSystemFinals.suffix(3).map { $0.text }.joined(separator: " ")
            if recentSystemFinals.contains(where: { Self.isEcho(event.text, $0.text) })
                || Self.isEcho(event.text, systemWindow) {
                app.dropUnfinalized(speaker: .self)
                return
            }
            app.dismissActiveCoach()
            await bus.publish(event)
            let lineID = app.upsertLine(event)
            recentMicFinals.append((lineID, event.id, event.text, Date()))
            if app.brief.isForeign { app.enqueueTranslation(id: lineID, text: event.text) }

            // Modo treino: a resposta do usuário realimenta o entrevistador (follow-up).
            training?.userSaid(event.text)

            // O interlocutor pode cair no mic como "self" mesmo quando o macOS diz
            // que a captura de sistema está ativa (stream sem sinal, caixa acústica,
            // roteamento da chamada). Perguntas sempre passam como locutor incerto;
            // o modelo decide se são uma deixa real ou responde NADA.
            if Self.shouldTriggerUncertainCoach(
                text: event.text,
                silenceMode: app.silenceMode,
                passiveMode: app.brief.mode.isPassive
            ) {
                app.currentQuestionID = lineID
                if consumeMatchingSpeculative(event.text) {
                    log.info("Final incerto consolidou dica especulativa")
                } else {
                    let window = await bus.window()
                    triggerCoach(window: window, latest: event.text, manual: false, speakerCertain: false)
                }
            }
        }
        app.recordDiagnostic(kind: .transcription, name: "stt_final", speaker: event.speaker)
        scheduleSummaryAfterFinal()
    }

    private func purgeEchoBuffers() {
        let cutoff = Date().addingTimeInterval(-echoWindow)
        recentSystemFinals.removeAll { $0.ts < cutoff }
        recentMicFinals.removeAll { $0.ts < cutoff }
    }

    /// Similaridade de contenção entre dois textos (palavras normalizadas).
    static func isEcho(_ a: String, _ b: String) -> Bool {
        let wa = normalizedWords(a), wb = normalizedWords(b)
        guard wa.count >= 2, wb.count >= 2 else { return false }
        if wa == wb { return true }
        let inter = wa.intersection(wb).count
        return Double(inter) / Double(min(wa.count, wb.count)) >= 0.75
    }

    private static func normalizedWords(_ s: String) -> Set<String> {
        Set(
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 1 }
        )
    }

    /// Heurística barata de "isso parece pergunta/deixa pro usuário?" (mic-only).
    static func looksLikeQuestion(_ t: String) -> Bool {
        if t.contains("?") { return true }
        let lower = t.lowercased()
        let starters = [
            "what", "why", "how", "when", "where", "which", "who", "could you",
            "can you", "tell me", "walk me", "describe", "would you", "do you",
            "have you", "let's", "o que", "por que", "como", "quando", "onde",
            "qual", "quem", "me conta", "me fala", "descreva", "você pode",
        ]
        return starters.contains { lower.hasPrefix($0) }
    }

    static func shouldTriggerUncertainCoach(text: String, silenceMode: Bool, passiveMode: Bool) -> Bool {
        !silenceMode && !passiveMode && looksLikeQuestion(text)
    }

    static func shouldBypassLiveDebounce(_ text: String) -> Bool {
        looksLikeQuestion(text)
    }

    // MARK: - Coaching

    private func consumeBusForCoaching() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            let stream = await self.bus.subscribe()
            for await event in stream {
                guard !self.app.silenceMode, !self.app.brief.mode.isPassive else { continue }
                // Gatilho: interlocutor terminou um turno.
                if event.speaker == .other, event.isFinal, event.isEndOfTurn {
                    if self.consumeMatchingSpeculative(event.text) { continue }
                    let window = await self.bus.window()
                    self.triggerCoach(window: window, latest: event.text, manual: false)
                }
            }
        }
    }

    private func consumeMatchingSpeculative(_ text: String) -> Bool {
        let normalized = SpeculativeTurnDetector.normalize(text)
        guard !speculativeText.isEmpty,
              normalized.hasPrefix(speculativeText) || speculativeText.hasPrefix(normalized) else { return false }
        speculativeText = ""
        return true
    }

    /// Live e manual têm filas independentes. Novos fragments live substituem apenas
    /// o pedido pendente; nunca cancelam uma chamada já enviada nem uma pergunta manual.
    private func triggerCoach(window: [Turn], latest: String, manual: Bool, speakerCertain: Bool = true) {
        let cardID = UUID()
        let instantGuide = manual ? nil : InstantCue.label(for: latest, mode: app.brief.mode)
        let request = CoachRequest(
            window: window,
            latest: latest,
            manual: manual,
            speakerCertain: speakerCertain,
            cardID: cardID,
            instantGuide: instantGuide,
            bypassDebounce: !manual && Self.shouldBypassLiveDebounce(latest),
            triggeredAt: .now
        )
        if let instantGuide {
            // Primeira orientação é puramente local: aparece antes de qualquer rede.
            app.upsertCoach(CoachCard(
                id: cardID,
                guidePT: instantGuide,
                kind: .answer,
                isStreaming: true
            ))
        }
        if manual {
            pendingManualCoach = request
            startNextManualCoachIfPossible()
        } else {
            pendingLiveCoach = request
            if request.bypassDebounce, liveCoachTask == nil {
                liveCoachDebounceTask?.cancel()
                liveCoachDebounceTask = nil
                startNextLiveCoach()
            } else {
                scheduleLiveCoachIfPossible()
            }
        }
        log.info(
            "Coach solicitado (manual: \(manual, privacy: .public), locutor certo: \(speakerCertain, privacy: .public))"
        )
    }

    /// Debounce curto: o STT costuma emitir vários finals próximos para o mesmo turno.
    private func scheduleLiveCoachIfPossible() {
        guard liveCoachTask == nil else { return }
        if pendingLiveCoach?.bypassDebounce == true {
            liveCoachDebounceTask?.cancel()
            liveCoachDebounceTask = nil
            startNextLiveCoach()
            return
        }
        liveCoachDebounceTask?.cancel()
        liveCoachDebounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(700)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.liveCoachDebounceTask = nil
            self.startNextLiveCoach()
        }
    }

    private func startNextLiveCoach() {
        guard liveCoachTask == nil, let request = pendingLiveCoach else { return }
        pendingLiveCoach = nil
        liveCoachTask = Task { [weak self] in
            guard let self else { return }
            await self.runCoach(request)
            self.liveCoachTask = nil
            if self.app.isRunning, self.pendingLiveCoach != nil {
                self.scheduleLiveCoachIfPossible()
            }
        }
    }

    private func startNextManualCoachIfPossible() {
        guard manualCoachTask == nil, let request = pendingManualCoach else { return }
        pendingManualCoach = nil
        manualCoachTask = Task { [weak self] in
            guard let self else { return }
            await self.runCoach(request)
            self.manualCoachTask = nil
            if self.app.isRunning, self.pendingManualCoach != nil {
                self.startNextManualCoachIfPossible()
            }
        }
    }

    private func runCoach(_ request: CoachRequest) async {
        app.coachBackendError = nil
        let queueMs = Self.milliseconds(since: request.triggeredAt)
        log.info(
            "Coach iniciou (manual: \(request.manual, privacy: .public), fila: \(queueMs, privacy: .public) ms)"
        )
        app.recordDiagnostic(kind: .coach, name: "requested", durationMs: queueMs)
        let fallbackTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(1_800)) }
            catch { return }
            guard let self,
                  let index = self.app.coachCards.firstIndex(where: { $0.id == request.cardID }),
                  self.app.coachCards[index].isStreaming,
                  self.app.coachCards[index].sayConversation == nil,
                  self.app.coachCards[index].sayNative.isEmpty else { return }
            var card = self.app.coachCards[index]
            card.guidePT = LatencyFallback.guide(for: request.latest, mode: self.app.brief.mode)
            self.app.upsertCoach(card)
            self.app.recordDiagnostic(kind: .coach, name: "local_fallback", durationMs: 1_800)
        }
        let stream = coachingLane.coach(
            window: request.window,
            latest: request.latest,
            manual: request.manual,
            speakerCertain: request.speakerCertain,
            cardID: request.cardID,
            initialGuide: request.instantGuide
        )
        do {
            var emittedUsefulCard = false
            var loggedFirstPhrase = false
            for try await card in stream {
                if Task.isCancelled { break }
                if !card.isStreaming {
                    emittedUsefulCard = card.hasContent
                }
                if !loggedFirstPhrase,
                   card.sayConversation != nil || !card.sayNative.isEmpty {
                    loggedFirstPhrase = true
                    let firstPhraseMs = Self.milliseconds(since: request.triggeredAt)
                    log.info(
                        "Coach primeira frase (manual: \(request.manual, privacy: .public), \(firstPhraseMs, privacy: .public) ms)"
                    )
                    app.recordDiagnostic(kind: .coach, name: "first_phrase", durationMs: firstPhraseMs)
                }
                app.upsertCoach(card)
            }
            guard !Task.isCancelled else { return }
            fallbackTask.cancel()
            app.pruneEmptyCoachCards()
            app.coachBackendReady = true
            let totalMs = Self.milliseconds(since: request.triggeredAt)
            log.info(
                "Coach concluído (manual: \(request.manual, privacy: .public), dica: \(emittedUsefulCard, privacy: .public), total: \(totalMs, privacy: .public) ms)"
            )
            app.recordDiagnostic(
                kind: .coach,
                name: emittedUsefulCard ? "completed" : "nothing_actionable",
                durationMs: totalMs
            )
        } catch {
            fallbackTask.cancel()
            guard !Task.isCancelled else { return }
            app.pruneEmptyCoachCards()
            app.coachBackendError = error.localizedDescription
            app.recordDiagnostic(kind: .error, name: "coach_failed", detail: "provider_error")
            log.error("Coaching falhou: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Resumo

    private func scheduleSummaryAfterFinal() {
        let thresholdReached = summaryPolicy.registerFinalTurn()
        if thresholdReached { summaryDebounceTask?.cancel() }
        guard summaryDebounceTask == nil || thresholdReached else { return }
        summaryDebounceTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(thresholdReached ? 2 : 8)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.summaryDebounceTask = nil
            guard self.summaryTask == nil else { return }
            self.summaryTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.runSummary(final: false)
                self.summaryTask = nil
            }
        }
    }

    private func runSummary(final: Bool) async {
        let started: ContinuousClock.Instant = .now
        let window = await bus.window()
        guard !window.isEmpty else { return }
        let summaryJob = Task { [summaryLane] in
            try await summaryLane.summarize(window: window)
        }
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(final ? 8 : 15)) }
            catch { return }
            summaryJob.cancel()
        }
        defer { timeout.cancel() }
        do {
            if let bullets = try await summaryJob.value {
                app.summaryBullets = bullets
                app.summaryBackendError = nil
                summaryPolicy.markSummarized()
                let elapsed = Self.milliseconds(since: started)
                app.recordDiagnostic(
                    kind: .summary,
                    name: final ? "final_completed" : "updated",
                    durationMs: elapsed
                )
                log.info("Resumo atualizado (\(bullets.count, privacy: .public) itens)")
            }
        } catch {
            guard !Task.isCancelled else { return }
            app.summaryBackendError = summaryJob.isCancelled
                ? "Resumo demorou demais; mantivemos a última versão."
                : error.localizedDescription
            app.recordDiagnostic(kind: .error, name: final ? "final_summary_failed" : "summary_failed")
            log.error("Resumo falhou: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int64 {
        let elapsed = start.duration(to: .now).components
        return elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
    }
}
