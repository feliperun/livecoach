import XCTest
@testable import CueMe

final class RelevantMemoryContextTests: XCTestCase {
    func testBuildsBoundedContextFromSemanticallyRankedNotes() {
        let relevantID = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
        let ignoredID = UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!
        let relevant = MemoryNote(
            id: relevantID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            summaryBullets: [],
            origin: .written,
            displayTitle: "Coragem em mudanças de carreira",
            noteKind: .journal,
            markdownBody: "Eu consigo explicar transições com serenidade e fatos.",
            labels: ["carreira"]
        )
        let ignored = MemoryNote(
            id: ignoredID,
            startedAt: Date(), mode: .recording, training: false,
            conversationLang: "pt-BR", nativeLang: "pt-BR", goal: "",
            transcript: [], coachCards: [], summaryBullets: [],
            origin: .written, displayTitle: "Receita", noteKind: .note,
            markdownBody: "Comprar pão."
        )

        let context = RelevantMemoryContextBuilder.format(
            records: [ignored, relevant],
            rankedIDs: [relevantID],
            characterLimit: 1_000
        )

        XCTAssertTrue(context?.contains("Coragem em mudanças de carreira") == true)
        XCTAssertTrue(context?.contains("transições com serenidade") == true)
        XCTAssertFalse(context?.contains("Comprar pão") == true)
    }

    func testCoachPromptUsesExplicitPersonalMemoryAsGroundedTruth() {
        var brief = SessionBrief.default
        brief.relevantMemoryContext = "Coragem em mudanças: conduzi uma transição com serenidade."

        let prompt = Prompts.coachSystem(brief: brief)

        XCTAssertTrue(prompt.contains("MEMÓRIA PESSOAL RELEVANTE"))
        XCTAssertTrue(prompt.contains("conduzi uma transição com serenidade"))
        XCTAssertTrue(prompt.contains("MEMÓRIA PESSOAL RELEVANTE acima"))
    }
}
