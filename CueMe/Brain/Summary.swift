import Foundation

/// Raia de resumo: sessão persistente (Haiku), fora do caminho crítico.
final class SummaryLane: Sendable {
    private let session: (any CoachSession)?

    init(session: (any CoachSession)?) {
        self.session = session
    }

    /// Resume a janela. Resposta vazia não apaga o último resumo válido.
    func summarize(window: [Turn]) async throws -> [String]? {
        guard let session, !window.isEmpty else { return nil }
        let text = try await session.complete(Prompts.summaryUser(window: window))
        let bullets = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { line -> String in
                var l = line
                while l.hasPrefix("-") || l.hasPrefix("•") || l.hasPrefix("*") {
                    l = String(l.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                // Remove markdown bold/itálico residual (**texto**, *texto*).
                l = l.replacingOccurrences(of: "**", with: "")
                return l.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
        let result = Array(bullets.prefix(5))
        return result.isEmpty ? nil : result
    }
}
