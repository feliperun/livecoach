import Foundation

enum GlobalMemoryAssistant {
    static func answer(records: [SessionRecord], request: String, model: CoachModel) async throws -> String {
        let client = ClaudeClient()
        let memory = records.enumerated().map { index, record in
            """
            [S\(index + 1)] \(record.title) — \(record.startedAt.formatted(date: .numeric, time: .shortened))
            \(context(for: record))
            """
        }.joined(separator: "\n\n---\n\n")
        let prompt = "PERGUNTA: \(request)\n\nMEMÓRIAS RECUPERADAS:\n\(String(memory.prefix(100_000)))"
        let candidates: [CoachModel] = model.isDeepSeek ? [model, .sonnet] : [model, .deepseekPro]
        var lastError: Error = SessionPostProcessorError.backendUnavailable
        for candidate in candidates {
            guard let session = client.makeCoachSession(model: candidate, system: systemPrompt) else { continue }
            do {
                let result = try await session.complete(prompt)
                await session.shutdown()
                guard !result.isEmpty else { throw SessionPostProcessorError.emptyResponse }
                return result + "\n\nFontes\n" + sourceList(records)
            } catch {
                lastError = error
                await session.shutdown()
            }
        }
        throw lastError
    }

    private static let systemPrompt = """
        Você responde perguntas sobre a memória de reuniões. Use somente as fontes fornecidas.
        Cite cada afirmação factual com [S1], [S2] etc. Diga claramente quando não houver evidência.
        Responda no idioma da pergunta e seja objetivo.
        """

    private static func sourceList(_ records: [SessionRecord]) -> String {
        records.enumerated().map { index, record in
            "[S\(index + 1)] \(record.title) — \(record.startedAt.formatted(date: .numeric, time: .shortened))"
        }.joined(separator: "\n")
    }

    private static func context(for record: SessionRecord) -> String {
        let transcript = record.transcript.filter(\.isFinal).map {
            "[\(record.participantName(for: $0.speaker))] \($0.text)"
        }.joined(separator: "\n")
        let topics = record.minutes.topics.map { "- \($0.title): \($0.summary)" }.joined(separator: "\n")
        let decisions = record.review.decisions.map { "- \($0.text)" }.joined(separator: "\n")
        let actions = record.takeaways.map { "- \($0.text)" }.joined(separator: "\n")
        return String("""
            Objetivo: \(record.goal)
            Resumo: \(record.minutes.overview)
            Assuntos:\n\(topics)
            Decisões:\n\(decisions)
            Ações:\n\(actions)
            Transcrição:\n\(transcript)
            """.prefix(60_000))
    }
}
