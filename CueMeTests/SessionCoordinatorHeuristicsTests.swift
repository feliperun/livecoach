import XCTest
@testable import CueMe

@MainActor
final class SessionCoordinatorHeuristicsTests: XCTestCase {
    func testEchoUsesNormalizedWordOverlap() {
        XCTAssertTrue(SessionCoordinator.isEcho(
            "Could you explain the deployment architecture?",
            "Explain the deployment architecture, could you?"
        ))
        XCTAssertFalse(SessionCoordinator.isEcho(
            "Tell me about your strengths",
            "I led a migration last year"
        ))
        XCTAssertTrue(SessionCoordinator.isEcho(
            "Ainda a expectativa",
            "ainda a expectativa"
        ))
        XCTAssertTrue(SessionCoordinator.isEcho(
            "vai vai a gente tem que",
            "né vai vai é a gente tem que ver"
        ))
    }

    func testQuestionHeuristicRecognizesInterviewPrompt() {
        XCTAssertTrue(SessionCoordinator.looksLikeQuestion("Tell me about a difficult project"))
        XCTAssertTrue(SessionCoordinator.looksLikeQuestion(
            "How did you plan for the migration, and what safeguards did you have?"
        ))
        XCTAssertFalse(SessionCoordinator.looksLikeQuestion("I finished the migration yesterday"))
    }

    func testQuestionOnUncertainChannelTriggersCoachEvenWhenCaptureMayExist() {
        XCTAssertTrue(SessionCoordinator.shouldTriggerUncertainCoach(
            text: "How did you plan for the migration?",
            silenceMode: false,
            passiveMode: false
        ))
        XCTAssertFalse(SessionCoordinator.shouldTriggerUncertainCoach(
            text: "How did you plan for the migration?",
            silenceMode: true,
            passiveMode: false
        ))
    }

    func testSummaryBackendFollowsSelectedCoachProvider() {
        XCTAssertEqual(
            SessionCoordinator.SummaryBackendSelection.resolve(for: .deepseekPro),
            .deepSeek(model: .deepseekFlash)
        )
        XCTAssertEqual(
            SessionCoordinator.SummaryBackendSelection.resolve(for: .sonnet),
            .claude(model: ClaudeClient.fastModel)
        )
    }

    func testLiveCoachUsesFastTierAndManualKeepsSelectedTier() {
        XCTAssertEqual(
            SessionCoordinator.CoachModelPlan.resolve(for: .deepseekPro),
            .init(live: .deepseekFlash, manual: .deepseekPro)
        )
        XCTAssertEqual(
            SessionCoordinator.CoachModelPlan.resolve(for: .opus),
            .init(live: .sonnet, manual: .opus)
        )
    }

    func testExplicitQuestionBypassesLiveDebounce() {
        XCTAssertTrue(SessionCoordinator.shouldBypassLiveDebounce(
            "How did you protect the migration?"
        ))
        XCTAssertFalse(SessionCoordinator.shouldBypassLiveDebounce(
            "We completed the migration last year."
        ))
    }

    func testInstantCueClassifiesQuestionWithoutNetwork() {
        XCTAssertEqual(
            InstantCue.label(for: "How did you plan the migration?", mode: .interview),
            "🧭 3 passos"
        )
        XCTAssertEqual(
            InstantCue.label(for: "Tell me about a difficult project", mode: .interview),
            "⭐ STAR"
        )
    }
}
