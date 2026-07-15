import Foundation

/// Deterministic, in-memory archive used only when the UI-test runner explicitly
/// launches CueMe with CUEME_UI_TESTING=1. It never writes into the user's archive.
enum UITestFixtures {
    struct Embedding: EmbeddingProvider {
        let modelID = "ui-test-semantic-v1"
        let dimensions = 512
        func embedding(for text: String) -> [Float] {
            var vector = [Float](repeating: 0, count: dimensions)
            let value = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if value.contains("veiculo") || value.contains("carro") || value.contains("sustentavel") {
                vector[17] = 1
            } else {
                vector[31] = 1
            }
            return vector
        }
    }

    struct Memory {
        let records: [SessionRecord]
        let projects: [KnowledgeProject]
        let people: [KnowledgePerson]
    }

    static var memory: Memory {
        let projectID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let sessionID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let earlierID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let evidenceID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let decisionID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        let turnID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let personID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let evidence = MemoryEvidence(
            id: evidenceID, turnID: turnID, timestamp: 42,
            quote: "O veículo elétrico será adotado no próximo trimestre."
        )
        let current = SessionRecord(
            id: sessionID, startedAt: now, endedAt: now.addingTimeInterval(1_800),
            mode: .meeting, training: false, conversationLang: "pt-BR", nativeLang: "pt-BR",
            goal: "Definir a estratégia de mobilidade", transcript: [
                TranscriptLine(
                    id: turnID, speaker: .other,
                    text: "O veículo elétrico será adotado no próximo trimestre.",
                    isFinal: true, ts: now.addingTimeInterval(42)
                )
            ], coachCards: [], summaryBullets: [],
            minutes: MeetingMinutes(
                overview: "A equipe aprovou a migração da frota.",
                topics: [.init(title: "Mobilidade", summary: "Troca gradual da frota por veículos elétricos.")]
            ), notes: [.init(timeOffset: 50, text: "Orçamento reservado para carregadores")],
            takeaways: [.init(
                text: "Solicitar propostas aos fornecedores", evidence: [evidence],
                confidence: 0.94, assignee: "Marina", createdInSessionID: sessionID
            )], displayTitle: "Estratégia de frota elétrica",
            review: MeetingReview(
                decisions: [.init(
                    id: decisionID, text: "Adotar veículos elétricos no próximo trimestre", evidence: [evidence],
                    confidence: 0.97, createdInSessionID: sessionID
                )],
                openQuestions: [.init(text: "Qual fornecedor terá melhor cobertura?", evidence: [evidence])]
            ), projectID: projectID, personIDs: [personID]
        )
        let earlier = SessionRecord(
            id: earlierID, startedAt: now.addingTimeInterval(-86_400),
            endedAt: now.addingTimeInterval(-84_600), mode: .meeting, training: false,
            conversationLang: "pt-BR", nativeLang: "pt-BR", goal: "Mapear custos",
            transcript: [], coachCards: [], summaryBullets: [],
            minutes: MeetingMinutes(overview: "Custos iniciais da frota foram levantados."),
            displayTitle: "Levantamento de custos", projectID: projectID
        )
        return Memory(
            records: [current, earlier],
            projects: [.init(id: projectID, name: "Projeto Mobilidade", summary: "Eletrificação da frota")],
            people: [.init(id: personID, name: "Marina", role: "Compras")]
        )
    }

    static func answer(for records: [SessionRecord]) -> String {
        guard let record = records.first else { return "Nenhuma memória relevante encontrada." }
        return "A frota elétrica foi aprovada para o próximo trimestre [S1].\n\nFontes\n[S1] \(record.title)"
    }
}
