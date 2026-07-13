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

    private var tasks: [Task<Void, Never>] = []
    private var coachTask: Task<Void, Never>?

    // Dedup de eco (setup alto-falante): a fala do interlocutor sai da caixa e volta
    // pelo mic. Guardamos finais recentes de cada lado e derrubamos duplicatas.
    private var recentSystemFinals: [(text: String, ts: Date)] = []
    private var recentMicFinals: [(id: UUID, text: String, ts: Date)] = []
    private let echoWindow: TimeInterval = 8

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
            app.sessionState = .error(error.localizedDescription)
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

        // Resumo rolante (debounce/coalesce por timer).
        tasks.append(summaryLoop())

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
            app.sessionState = .error(error.localizedDescription)
            return
        }
        app.systemCaptureActive = capture.isSystemActive
        tasks.append(routeAudio(from: capture))

        // Gravação do áudio original, sincronizada com a transcrição (opt-out).
        if app.recordAudio, let sessionID = app.currentSessionID {
            let rec = MeetingRecorder()
            do {
                try await rec.start(directory: MeetingRecording.directory(for: sessionID))
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

    /// Para a sessão e devolve a duração gravada (nil se não gravou nada).
    func stop() async -> TimeInterval? {
        coachTask?.cancel()
        coachTask = nil
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

        for s in sessions { await s.shutdown() }
        sessions.removeAll()
        summaryLane = SummaryLane(session: nil)
        coachingLane = CoachingLane(live: nil, manual: nil)
        app.stopTranslation()
        app.systemCaptureActive = false
        log.info("Sessão parada")
        return duration
    }

    /// Cria as sessões persistentes das raias e as AQUECE. Resumo usa o Claude CLI
    /// (se existir); o coach usa o backend do modelo escolhido (DeepSeek HTTP ou CLI).
    private func buildBrain(brief: SessionBrief) {
        // Resumo é útil em qualquer modo (inclusive reunião — notas da conversa).
        // Só roda com o Claude CLI presente; sem ele, fica desligado.
        if client.isAvailable {
            let summarySession = client.makeSession(model: ClaudeClient.fastModel, system: Prompts.summarySystem(brief: brief))
            summaryLane = SummaryLane(session: summarySession)
            sessions = [summarySession].compactMap { $0 }
        }

        // Modo reunião é passivo (tema livre) — o coach não se aplica, não gasta sessão.
        guard !brief.mode.isPassive else { return }

        let coachSystem = Prompts.coachSystem(brief: brief)
        // Live coach usa o modelo escolhido pelo usuário (DeepSeek Pro default).
        let coachLive = client.makeCoachSession(model: app.coachModel, system: coachSystem)
        // Input manual usa o tier rápido do mesmo provedor: DeepSeek Flash ou Sonnet.
        let manualModel: CoachModel = app.coachModel.isDeepSeek ? .deepseekFlash : .sonnet
        let coachManual = client.makeCoachSession(model: manualModel, system: coachSystem)

        coachingLane = CoachingLane(live: coachLive, manual: coachManual)
        sessions += [coachLive, coachManual].compactMap { $0 }

        // Prewarm: paga cold start / TLS agora, antes da 1ª pergunta. O coach é o
        // crítico (resumo é background, não vale poluir o histórico dele com aquecimento).
        coachLive?.prewarm()
        coachManual?.prewarm()
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

    // MARK: - Consumo de eventos de STT

    private func consume(events: AsyncStream<TranscriptEvent>) -> Task<Void, Never> {
        Task { [weak self] in
            for await event in events {
                guard let self else { break }
                if event.isFinal {
                    await self.handleFinal(event)
                } else {
                    self.app.upsertLine(event)
                }
            }
        }
    }

    private func handleFinal(_ event: TranscriptEvent) async {
        purgeEchoBuffers()

        switch event.speaker {
        case .other:
            // Registra pra derrubar o eco que chegar pelo mic; remove eco que já chegou.
            recentSystemFinals.append((event.text, Date()))
            if let dupe = recentMicFinals.first(where: { Self.isEcho($0.text, event.text) }) {
                app.removeLine(id: dupe.id)
                recentMicFinals.removeAll { $0.id == dupe.id }
            }
            await bus.publish(event)
            let lineID = app.upsertLine(event)
            app.currentQuestionID = lineID          // pergunta/deixa mais recente no topo
            if app.brief.isForeign { app.enqueueTranslation(id: lineID, text: event.text) }

        case .self:
            // Eco da caixa de som? (interlocutor já transcrito pelo stream de sistema)
            if recentSystemFinals.contains(where: { Self.isEcho(event.text, $0.text) }) {
                app.dropUnfinalized(speaker: .self)
                return
            }
            await bus.publish(event)
            let lineID = app.upsertLine(event)
            recentMicFinals.append((lineID, event.text, Date()))
            if app.brief.isForeign { app.enqueueTranslation(id: lineID, text: event.text) }

            // Modo treino: a resposta do usuário realimenta o entrevistador (follow-up).
            training?.userSaid(event.text)

            // Mic-only (sem captura de sistema): o interlocutor entra pelo mic como
            // "self". Se parece pergunta/deixa, destaca e aciona o coach com locutor
            // incerto — o modelo decide (card ou NADA).
            if !app.systemCaptureActive, !app.silenceMode, !app.brief.mode.isPassive, Self.looksLikeQuestion(event.text) {
                app.currentQuestionID = lineID
                let window = await bus.window()
                triggerCoach(window: window, latest: event.text, manual: false, speakerCertain: false)
            }
        }
    }

    private func purgeEchoBuffers() {
        let cutoff = Date().addingTimeInterval(-echoWindow)
        recentSystemFinals.removeAll { $0.ts < cutoff }
        recentMicFinals.removeAll { $0.ts < cutoff }
    }

    /// Similaridade de contenção entre dois textos (palavras normalizadas).
    static func isEcho(_ a: String, _ b: String) -> Bool {
        let wa = normalizedWords(a), wb = normalizedWords(b)
        guard wa.count >= 3, wb.count >= 3 else { return false }
        let inter = wa.intersection(wb).count
        return Double(inter) / Double(min(wa.count, wb.count)) >= 0.75
    }

    private static func normalizedWords(_ s: String) -> Set<String> {
        Set(
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
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

    // MARK: - Coaching

    private func consumeBusForCoaching() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            let stream = await self.bus.subscribe()
            for await event in stream {
                guard !self.app.silenceMode, !self.app.brief.mode.isPassive else { continue }
                // Gatilho: interlocutor terminou um turno.
                if event.speaker == .other, event.isFinal, event.isEndOfTurn {
                    let window = await self.bus.window()
                    self.triggerCoach(window: window, latest: event.text, manual: false)
                }
            }
        }
    }

    /// Cancela o coaching anterior e dispara um novo (por turno).
    private func triggerCoach(window: [Turn], latest: String, manual: Bool, speakerCertain: Bool = true) {
        coachTask?.cancel()
        coachTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.coachingLane.coach(window: window, latest: latest, manual: manual, speakerCertain: speakerCertain)
            do {
                for try await card in stream {
                    if Task.isCancelled { break }
                    self.app.upsertCoach(card)
                }
            } catch {
                self.log.error("Coaching falhou: \(error.localizedDescription, privacy: .public)")
            }
            // Limpa o placeholder instantâneo se o coach não teve nada a dizer (NADA).
            if !Task.isCancelled { self.app.pruneEmptyCoachCards() }
        }
    }

    // MARK: - Resumo

    private func summaryLoop() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { break }
                let window = await self.bus.window()
                if let bullets = await self.summaryLane.summarize(window: window) {
                    self.app.summaryBullets = bullets
                }
            }
        }
    }
}
