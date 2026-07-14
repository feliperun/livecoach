import XCTest
@testable import CueMe

final class CoachCardParserTests: XCTestCase {
    func testParsesGlanceCard() throws {
        let text = """
        GUIA: 📈 Mostre impacto concreto
        DIGA: I reduced deployment time by forty percent.
        PT: Reduzi o tempo de deploy em quarenta por cento.
        KEY: deployment time · forty percent
        """

        let card = try XCTUnwrap(
            CoachCardParser.parse(text, id: UUID(), manual: false, streaming: false)
        )
        XCTAssertEqual(card.guidePT, "📈 Mostre impacto concreto")
        XCTAssertEqual(card.sayConversation, "I reduced deployment time by forty percent.")
        XCTAssertEqual(card.keytermsConversation, ["deployment time", "forty percent"])
        XCTAssertFalse(card.isStreaming)
    }

    func testNadaProducesNoCard() {
        XCTAssertNil(CoachCardParser.parse("NADA", id: UUID(), manual: false, streaming: false))
    }

    func testUnstructuredOrEmptyResponseProducesNoCard() {
        XCTAssertNil(CoachCardParser.parse("Vou pensar sobre isso.", id: UUID(), manual: false, streaming: false))
        XCTAssertNil(CoachCardParser.parse("", id: UUID(), manual: false, streaming: false))
    }

    func testPhraseCanRenderBeforeSecondaryFieldsArrive() throws {
        let card = try XCTUnwrap(
            CoachCardParser.parse(
                "DIGA: We migrated in controlled stages.",
                id: UUID(),
                manual: false,
                streaming: true
            )
        )

        XCTAssertEqual(card.sayConversation, "We migrated in controlled stages.")
        XCTAssertTrue(card.guidePT.isEmpty)
        XCTAssertTrue(card.isStreaming)
    }
}
