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
    var coachModel: CoachModel = .sonnet   // default rápido; Opus disponível no picker
    var echoCancellation: Bool = false     // AEC experimental (sem fones); default off
    var trainingMode: Bool = false         // entrevistador por voz (teste e2e + prep solo)
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
    var currentQuestionID: UUID?           // última pergunta/deixa do interlocutor

    /// Tradução nativa on-device: config observável aqui, loop no pipe (Sendable).
    /// A RootView pluga `.translationTask(translationConfig)`.
    var translationConfig: TranslationSession.Configuration?
    @ObservationIgnored nonisolated let translationPipe = TranslationPipe()

    private var coordinator: SessionCoordinator?

    init() {
        self.brief = BriefStore.load()
        self.backendAvailable = ClaudeClient().isAvailable
        translationPipe.onResult = { [weak self] id, text in
            Task { @MainActor in self?.setTranslation(lineID: id, translation: text) }
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
        let coord = SessionCoordinator(app: self)
        self.coordinator = coord
        Task { await coord.start() }
    }

    func stop() {
        Task { [coordinator] in
            await coordinator?.stop()
        }
        coordinator = nil
        sessionState = .idle
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
        backendAvailable = ClaudeClient().isAvailable
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
}
