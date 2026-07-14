import XCTest
@testable import CueMe

final class SessionRuntimeTests: XCTestCase {
    func testStablePartialTriggersOnceBeforeFinal() {
        var detector = SpeculativeTurnDetector()
        let question = "How did you plan the migration?"
        XCTAssertFalse(detector.observe(question, looksActionable: { _ in true }))
        XCTAssertTrue(detector.observe(question, looksActionable: { _ in true }))
        XCTAssertFalse(detector.observe(question, looksActionable: { _ in true }))
        detector.finalize()
        XCTAssertFalse(detector.observe(question, looksActionable: { _ in true }))
    }

    func testSummaryRunsAfterThreeNewFinalTurns() {
        var policy = SummarySchedulePolicy()
        XCTAssertFalse(policy.registerFinalTurn())
        XCTAssertFalse(policy.registerFinalTurn())
        XCTAssertTrue(policy.registerFinalTurn())
        policy.markSummarized()
        XCTAssertFalse(policy.registerFinalTurn())
        XCTAssertTrue(policy.hasUnsummarizedTurns)
    }

    func testDiagnosticsAggregateLatencyWithoutConversationContent() {
        var diagnostics = SessionDiagnostics()
        diagnostics.record(.init(kind: .coach, name: "first_phrase", durationMs: 500))
        diagnostics.record(.init(kind: .coach, name: "first_phrase", durationMs: 700))
        XCTAssertEqual(diagnostics.count("first_phrase"), 2)
        XCTAssertEqual(diagnostics.averageMs("first_phrase"), 600)
    }

    func testLatencyFallbackIsVisualAndShort() {
        XCTAssertEqual(
            LatencyFallback.guide(for: "How did you ship it?", mode: .interview),
            "PLANO → AÇÃO → RESULTADO"
        )
    }
}
