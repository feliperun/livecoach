import Foundation

/// Barramento central: recebe eventos de STT, faz fan-out para os consumidores
/// (tradução, resumo, coach, UI) e mantém a janela rolante de turnos finalizados.
actor TranscriptBus {
    private var subscribers: [UUID: AsyncStream<TranscriptEvent>.Continuation] = [:]
    private var turns: [Turn] = []
    private let maxTurns: Int

    init(maxTurns: Int = 40) {
        self.maxTurns = maxTurns
    }

    func publish(_ event: TranscriptEvent) {
        if event.isFinal {
            appendTurn(id: event.id, speaker: event.speaker, text: event.text)
        }
        for cont in subscribers.values {
            cont.yield(event)
        }
    }

    /// Cada chamada devolve um stream independente (fan-out).
    func subscribe() -> AsyncStream<TranscriptEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(256)) { cont in
            subscribers[id] = cont
            cont.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(id) }
            }
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    /// Janela rolante (últimos N turnos) para resumo e coach.
    func window() -> [Turn] { turns }

    /// Adiciona um turno de input manual do usuário (aparece no contexto do coach).
    func appendManual(_ text: String) {
        appendTurn(speaker: .self, text: text)
    }

    /// Remove um turno que depois se confirmou como eco do áudio de sistema.
    func removeTurn(id: UUID) {
        turns.removeAll { $0.id == id }
    }

    func finish() {
        for cont in subscribers.values { cont.finish() }
        subscribers.removeAll()
    }

    private func appendTurn(id: UUID = UUID(), speaker: Speaker, text: String) {
        // Coalesce: se o mesmo locutor emite finals seguidos, ainda registramos
        // como turnos distintos — o transcript é a fonte da verdade fina.
        turns.append(Turn(id: id, speaker: speaker, text: text))
        if turns.count > maxTurns {
            turns.removeFirst(turns.count - maxTurns)
        }
    }
}
