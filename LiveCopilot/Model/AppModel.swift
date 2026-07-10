import Foundation
import Observation

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
    var coachModel: CoachModel = .opus     // modelo do live coach (crítico)
    var manualInput: String = ""
    var silenceMode: Bool = false          // pausa o coach, mantém transcript
    var backendAvailable: Bool             // Claude Code CLI encontrado?
    var systemCaptureActive: Bool = false  // ScreenCaptureKit capturando o interlocutor?

    private var coordinator: SessionCoordinator?

    init() {
        self.brief = BriefStore.load()
        self.backendAvailable = ClaudeClient().isAvailable
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

    func setTranslation(lineID: UUID, translation: String) {
        guard let idx = transcript.firstIndex(where: { $0.id == lineID }) else { return }
        transcript[idx].translation = translation
    }

    /// Encontra a última linha final de um locutor (para anexar tradução).
    func lastFinalLineID(speaker: Speaker, matching text: String) -> UUID? {
        transcript.last(where: { $0.speaker == speaker && $0.isFinal && $0.text == text })?.id
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
