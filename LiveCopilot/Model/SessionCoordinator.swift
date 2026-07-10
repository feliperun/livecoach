import Foundation
import OSLog

/// Orquestra a sessão ao vivo: captura → STT (por origem) → barramento → raias → UI.
/// Vive no `@MainActor`; o trabalho pesado (rede, áudio, STT) roda em actors/URLSession
/// que suspendem fora da main thread nos `await`.
@MainActor
final class SessionCoordinator {
    private let log = Logger(subsystem: "LiveCopilot", category: "SessionCoordinator")
    private unowned let app: AppModel

    private let bus = TranscriptBus()
    private let client = ClaudeClient()

    // Raias e sessões persistentes (warm), criadas no start() com o brief atual.
    private var translationLane = TranslationLane(sessions: [])
    private var summaryLane = SummaryLane(session: nil)
    private var coachingLane = CoachingLane(live: nil, manual: nil)
    private var sessions: [ClaudeSession] = []

    private var capture: AudioCapture?
    private var micStt: (any SttSession)?
    private var systemStt: (any SttSession)?

    private var tasks: [Task<Void, Never>] = []
    private var coachTask: Task<Void, Never>?

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

        // Sessões persistentes do Claude CLI (warm após 1º uso). System prompt e
        // modelo fixos por sessão, derivados do brief.
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
            try await capture.start(includeSystem: true)
        } catch {
            app.sessionState = .error(error.localizedDescription)
            return
        }
        app.systemCaptureActive = capture.isSystemActive
        tasks.append(routeAudio(from: capture))

        app.sessionState = .running
        log.info("Sessão iniciada")
    }

    func stop() async {
        coachTask?.cancel()
        coachTask = nil
        for t in tasks { t.cancel() }
        tasks.removeAll()

        capture?.finish()
        capture = nil
        await micStt?.finish()
        await systemStt?.finish()
        micStt = nil
        systemStt = nil
        await bus.finish()

        for s in sessions { await s.shutdown() }
        sessions.removeAll()
        translationLane = TranslationLane(sessions: [])
        summaryLane = SummaryLane(session: nil)
        coachingLane = CoachingLane(live: nil, manual: nil)
        app.systemCaptureActive = false
        log.info("Sessão parada")
    }

    /// Cria as sessões persistentes das raias (só se o CLI existir).
    private func buildBrain(brief: SessionBrief) {
        guard client.isAvailable else { return }

        // Tradução: pool (round-robin) só quando a conversa é estrangeira.
        let translateSessions: [ClaudeSession] = brief.isForeign
            ? (0..<3).compactMap { _ in
                client.makeSession(model: ClaudeClient.fastModel, system: Prompts.translateSystem(brief: brief))
              }
            : []
        let summarySession = client.makeSession(model: ClaudeClient.fastModel, system: Prompts.summarySystem(brief: brief))
        // Live coach usa o modelo escolhido pelo usuário (Opus default).
        let coachLive = client.makeSession(model: app.coachModel.cliAlias, system: Prompts.coachSystem(brief: brief))
        // Input manual sempre Sonnet.
        let coachManual = client.makeSession(model: ClaudeClient.liveModel, system: Prompts.coachSystem(brief: brief))

        translationLane = TranslationLane(sessions: translateSessions)
        summaryLane = SummaryLane(session: summarySession)
        coachingLane = CoachingLane(live: coachLive, manual: coachManual)

        sessions = (translateSessions + [summarySession, coachLive, coachManual]).compactMap { $0 }
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
            }
        }
    }

    // MARK: - Consumo de eventos de STT

    private func consume(events: AsyncStream<TranscriptEvent>) -> Task<Void, Never> {
        Task { [weak self] in
            for await event in events {
                guard let self else { break }
                await self.bus.publish(event)
                let lineID = self.app.upsertLine(event)

                if event.isFinal {
                    self.translate(event: event, lineID: lineID)
                }
            }
        }
    }

    private func translate(event: TranscriptEvent, lineID: UUID) {
        let brief = app.brief
        guard brief.isForeign else { return }
        Task { [weak self] in
            guard let self else { return }
            if let translated = await self.translationLane.translate(event.text) {
                self.app.setTranslation(lineID: lineID, translation: translated)
            }
        }
    }

    // MARK: - Coaching

    private func consumeBusForCoaching() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            let stream = await self.bus.subscribe()
            for await event in stream {
                guard !self.app.silenceMode else { continue }
                // Gatilho: interlocutor terminou um turno.
                if event.speaker == .other, event.isFinal, event.isEndOfTurn {
                    let window = await self.bus.window()
                    self.triggerCoach(window: window, latest: event.text, manual: false)
                }
            }
        }
    }

    /// Cancela o coaching anterior e dispara um novo (por turno).
    private func triggerCoach(window: [Turn], latest: String, manual: Bool) {
        coachTask?.cancel()
        coachTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.coachingLane.coach(window: window, latest: latest, manual: manual)
            do {
                for try await card in stream {
                    if Task.isCancelled { break }
                    self.app.upsertCoach(card)
                }
            } catch {
                self.log.error("Coaching falhou: \(error.localizedDescription, privacy: .public)")
            }
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
