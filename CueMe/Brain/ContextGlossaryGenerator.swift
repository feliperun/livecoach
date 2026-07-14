import Foundation

enum ContextGlossaryGeneratorError: LocalizedError {
    case backendUnavailable
    case emptyResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .backendUnavailable: return "O modelo do glossário não está disponível."
        case .emptyResponse: return "O modelo não retornou termos úteis."
        case .timedOut: return "O glossário demorou demais; a sessão seguirá sem ele."
        }
    }
}

enum ContextGlossaryGenerator {
    private static let system = """
    Você é um terminologista de reconhecimento de fala. Sua única função é extrair
    keyterms de alta precisão para a Deepgram. Obedeça rigorosamente o formato JSON,
    os limites pedidos e nunca invente entidades ausentes nas fontes fornecidas.
    """

    static func generate(
        contexts: [MeetingContext],
        brief: SessionBrief,
        model: CoachModel,
        client: ClaudeClient = ClaudeClient()
    ) async throws -> [String] {
        guard let session = client.makeCoachSession(model: model, system: system) else {
            throw ContextGlossaryGeneratorError.backendUnavailable
        }
        do {
            let prompt = ContextGlossaryRequest.prompt(contexts: contexts, brief: brief)
            let response = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await session.complete(prompt) }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    await session.shutdown()
                    throw ContextGlossaryGeneratorError.timedOut
                }
                guard let first = try await group.next() else {
                    throw ContextGlossaryGeneratorError.emptyResponse
                }
                group.cancelAll()
                return first
            }
            await session.shutdown()
            let terms = ContextGlossaryParser.parse(response)
            guard !terms.isEmpty else { throw ContextGlossaryGeneratorError.emptyResponse }
            return terms
        } catch {
            await session.shutdown()
            throw error
        }
    }
}
