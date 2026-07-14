import Foundation

/// Abstração de uma sessão de LLM para as raias de coach/resumo. Duas
/// implementações: `ClaudeSession` (processo `claude` CLI, sem API key) e
/// `DeepSeekSession` (HTTP direto à API DeepSeek, streaming SSE). A raia não
/// sabe qual backend está por trás — só consome deltas de texto.
protocol CoachSession: Sendable {
    /// Stream de deltas de texto de um turno.
    func send(_ user: String) async -> AsyncThrowingStream<String, Error>

    /// Coleta o stream inteiro num texto só (resumo/pergunta única).
    func complete(_ user: String) async throws -> String

    /// Aquece o backend (paga cold start / TLS antes do 1º turno real).
    /// O erro precisa chegar à UI; um warm-up silencioso mascara auth/rate limit.
    func prewarm() async throws

    /// Encerra a sessão e libera recursos.
    func shutdown() async
}

extension ClaudeSession: CoachSession {}
