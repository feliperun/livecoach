import XCTest
@testable import CueMe

final class SessionPostProcessorTests: XCTestCase {
    func testParseTakeawaysAcceptsChecklistBulletsAndNumberedItems() {
        let output = """
        - [ ] Enviar proposta até sexta
        - Confirmar o responsável técnico
        3. Marcar o próximo encontro
        """

        let items = SessionPostProcessor.parseTakeaways(output)

        XCTAssertEqual(items.map(\.text), [
            "Enviar proposta até sexta",
            "Confirmar o responsável técnico",
            "Marcar o próximo encontro"
        ])
        XCTAssertTrue(items.allSatisfy { !$0.isDone })
    }

    func testContextIncludesNotesSummaryAndBothSpeakers() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let record = SessionRecord(
            startedAt: startedAt,
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "Planejar entrega",
            transcript: [
                .init(speaker: .self, text: "Eu preparo o plano.", isFinal: true, ts: startedAt),
                .init(speaker: .other, text: "Eu reviso amanhã.", isFinal: true, ts: startedAt)
            ],
            coachCards: [],
            summaryBullets: ["Plano será preparado."],
            notes: [.init(timeOffset: 4, text: "Validar prazo")]
        )

        let context = SessionPostProcessor.context(for: record)

        XCTAssertTrue(context.contains("Objetivo: Planejar entrega"))
        XCTAssertTrue(context.contains("Resumo atual:\n- Plano será preparado."))
        XCTAssertTrue(context.contains("Nota 00:04: Validar prazo"))
        XCTAssertTrue(context.contains("[VOCÊ] Eu preparo o plano."))
        XCTAssertTrue(context.contains("[INTERLOCUTOR] Eu reviso amanhã."))
    }
}
