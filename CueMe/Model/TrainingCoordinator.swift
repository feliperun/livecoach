import Foundation
import AVFoundation
import OSLog

/// Modo Treino: um ENTREVISTADOR (sessão Claude CLI) lê a pauta + CV, gera perguntas
/// e as FALA por TTS nativo. O áudio sai pela saída do sistema e é captado pelo
/// próprio ScreenCaptureKit como `other` → exercita STT → tradução → coach (teste
/// e2e real). As respostas do usuário (mic, `self`) realimentam o entrevistador,
/// que faz o follow-up. Conversa adaptativa, sem key, sem app externo.
@MainActor
final class TrainingCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    private let log = Logger(subsystem: "CueMe", category: "Training")

    private let client: ClaudeClient
    private let brief: SessionBrief
    private var interviewer: ClaudeSession?

    private let synth = AVSpeechSynthesizer()
    private(set) var speaking = false

    // Debounce da resposta do usuário: acumula falas e dispara o follow-up após silêncio.
    private var pendingAnswer = ""
    private var followUpTask: Task<Void, Never>?
    private let answerDebounce: Duration = .seconds(3)

    var onQuestionStart: (() -> Void)?   // opcional: UI pode reagir

    init(client: ClaudeClient, brief: SessionBrief) {
        self.client = client
        self.brief = brief
        super.init()
        synth.delegate = self
    }

    func start() {
        interviewer = client.makeSession(
            model: ClaudeClient.liveModel,
            system: Prompts.interviewerSystem(brief: brief)
        )
        // Primeira pergunta.
        Task { await ask(opening: true, answer: nil) }
    }

    func stop() {
        followUpTask?.cancel()
        followUpTask = nil
        synth.stopSpeaking(at: .immediate)
        speaking = false
        Task { [interviewer] in await interviewer?.shutdown() }
        interviewer = nil
    }

    /// Chamado quando o usuário (mic, `self`) diz algo final. Debounce → follow-up.
    func userSaid(_ text: String) {
        // Ignora o eco da própria pergunta enquanto o entrevistador fala.
        guard !speaking, interviewer != nil else { return }
        pendingAnswer += (pendingAnswer.isEmpty ? "" : " ") + text
        followUpTask?.cancel()
        followUpTask = Task { [weak self] in
            try? await Task.sleep(for: self?.answerDebounce ?? .seconds(3))
            guard let self, !Task.isCancelled else { return }
            let answer = self.pendingAnswer
            self.pendingAnswer = ""
            await self.ask(opening: false, answer: answer)
        }
    }

    // MARK: - Geração + fala

    private func ask(opening: Bool, answer: String?) async {
        guard let interviewer else { return }
        let user = Prompts.interviewerTurn(candidateAnswer: answer, opening: opening)
        guard let question = try? await interviewer.complete(user), !question.isEmpty else { return }
        speak(question)
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: brief.conversationLang)
            ?? AVSpeechSynthesisVoice(language: SessionBrief.baseCode(brief.conversationLang))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        speaking = true
        onQuestionStart?()
        log.info("Entrevistador fala: \(text.prefix(60), privacy: .public)…")
        synth.speak(utterance)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }
}
