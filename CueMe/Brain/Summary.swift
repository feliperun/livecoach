import Foundation

/// Raia de ata: sessão persistente e fora do caminho crítico.
final class SummaryLane: Sendable {
    private let session: (any CoachSession)?

    init(session: (any CoachSession)?) {
        self.session = session
    }

    /// Mescla apenas os novos turnos na ata existente. Resposta inválida ou vazia
    /// nunca apaga a última versão válida.
    func summarize(existing: MeetingMinutes, newTurns: [Turn]) async throws -> MeetingMinutes? {
        guard let session, !newTurns.isEmpty else { return nil }
        let text = try await session.complete(Prompts.summaryUser(existing: existing, newTurns: newTurns))
        return MeetingMinutes.parse(modelOutput: text, preserving: existing)
    }
}
