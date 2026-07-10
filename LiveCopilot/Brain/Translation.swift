import Foundation

/// Raia de tradução: POOL de sessões persistentes (Haiku), round-robin, para
/// acompanhar fala rápida sem enfileirar tudo numa conversa serial só.
/// System prompt do tradutor fica fixo nas sessões; aqui só mandamos a fala.
final class TranslationLane: @unchecked Sendable {
    private let sessions: [ClaudeSession]
    private let lock = NSLock()
    private var next = 0

    init(sessions: [ClaudeSession]) {
        self.sessions = sessions
    }

    private func pick() -> ClaudeSession? {
        guard !sessions.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        let s = sessions[next % sessions.count]
        next += 1
        return s
    }

    /// Traduz uma fala. Retorna nil se não há sessão ou em falha (degrada silencioso).
    func translate(_ text: String) async -> String? {
        guard let session = pick() else { return nil }
        let result = try? await session.complete(Prompts.translateUser(text))
        guard let result, !result.isEmpty else { return nil }
        return result
    }
}
