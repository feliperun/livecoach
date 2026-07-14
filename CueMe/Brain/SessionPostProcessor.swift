import Foundation

enum SessionPostProcessorError: LocalizedError {
    case backendUnavailable
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .backendUnavailable: return "O assistente não está disponível."
        case .emptyResponse: return "O assistente não retornou conteúdo."
        }
    }
}

enum SessionPostProcessor {
    static func generate(
        record: SessionRecord,
        request: String,
        kind: SessionArtifactKind,
        model: CoachModel
    ) async throws -> String {
        let client = ClaudeClient()
        let prompt = """
            PEDIDO:
            \(request)

            MEMÓRIA DA SESSÃO:
            \(context(for: record))
            """
        let models: [CoachModel] = model.isDeepSeek ? [model, .sonnet] : [model, .deepseekPro]
        var lastError: Error = SessionPostProcessorError.backendUnavailable
        for candidate in models {
            guard let session = client.makeCoachSession(
                model: candidate,
                system: systemPrompt(language: record.nativeLang, kind: kind)
            ) else { continue }
            do {
                let result = try await session.complete(prompt)
                await session.shutdown()
                guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SessionPostProcessorError.emptyResponse
                }
                return result
            } catch {
                lastError = error
                await session.shutdown()
            }
        }
        throw lastError
    }

    static func context(for record: SessionRecord) -> String {
        var parts = [
            "Título: \(record.title)",
            "Objetivo: \(record.goal)",
            "Data: \(record.startedAt.formatted(date: .long, time: .shortened))"
        ]
        if !record.minutes.isEmpty {
            let topics = record.minutes.topics.map { "- \($0.title): \($0.summary)" }.joined(separator: "\n")
            parts.append("Ata atual:\n\(record.minutes.overview)\n\(topics)")
        } else if !record.summaryBullets.isEmpty {
            parts.append("Resumo atual:\n" + record.summaryBullets.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !record.notes.isEmpty {
            let notes = record.notes.map {
                "Nota \(SessionArchive.clock($0.timeOffset)): \($0.text)"
            }.joined(separator: "\n")
            parts.append("Anotações:\n\(notes)")
        }
        let transcript = record.transcript.filter(\.isFinal).map { line in
            let speaker = record.participantName(for: line.speaker).uppercased()
            let translation = line.translation.map { " | Tradução: \($0)" } ?? ""
            return "[\(speaker)] \(line.text)\(translation)"
        }.joined(separator: "\n")
        parts.append("Transcrição:\n\(transcript.isEmpty ? "(vazia)" : transcript)")
        return String(parts.joined(separator: "\n\n").prefix(60_000))
    }

    static func parseTakeaways(_ output: String) -> [SessionTakeaway] {
        let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.uppercased() != "NENHUMA" else { return [] }
        return normalized.split(whereSeparator: \Character.isNewline).compactMap { raw in
            var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* "] where text.hasPrefix(prefix) {
                text.removeFirst(prefix.count)
                break
            }
            if let dot = text.firstIndex(of: "."),
               !text[..<dot].isEmpty,
               text[..<dot].allSatisfy(\.isNumber) {
                text = String(text[text.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
            }
            guard !text.isEmpty else { return nil }
            return SessionTakeaway(text: text)
        }
    }

    private static func systemPrompt(language: String, kind: SessionArtifactKind) -> String {
        let native = Prompts.langName(language)
        let format: String
        switch kind {
        case .summary:
            format = """
            Responda SOMENTE JSON válido: {"overview":"um parágrafo","topics":[{"title":"Assunto","summary":"mini resumo"}]}. Use no máximo 12 assuntos.
            """
        case .takeaways:
            format = "Liste apenas ações ainda pendentes como '- [ ] ação'. Se não houver, responda NENHUMA."
        case .answer, .custom:
            format = "Responda de forma objetiva e organizada; use Markdown simples quando ajudar."
        }
        return """
        Você é um assistente de memória pós-reunião. Responda em \(native) e use SOMENTE
        a memória fornecida. Diferencie fatos, decisões e inferências; nunca invente nomes,
        prazos ou compromissos. \(format)
        """
    }
}
