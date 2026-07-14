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

    func testSummaryIsRateLimitedBySemanticBatchAndTime() {
        let start = Date(timeIntervalSince1970: 1_000)
        var policy = SummarySchedulePolicy(startedAt: start)
        for offset in 0..<7 {
            XCTAssertFalse(policy.registerFinalTurn(at: start.addingTimeInterval(Double(offset))))
        }
        XCTAssertTrue(policy.registerFinalTurn(at: start.addingTimeInterval(45)))
        policy.markSummarized(at: start.addingTimeInterval(45))
        for offset in 0..<11 {
            XCTAssertFalse(policy.registerFinalTurn(at: start.addingTimeInterval(46 + Double(offset))))
        }
        XCTAssertFalse(policy.registerFinalTurn(at: start.addingTimeInterval(100)))
        XCTAssertTrue(policy.registerFinalTurn(at: start.addingTimeInterval(166)))
        XCTAssertTrue(policy.hasUnsummarizedTurns)
    }

    func testMeetingCoachRequiresNovelHighValueMomentAndCooldown() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(CoachTriggerPolicy.shouldTrigger(
            text: "Aqui estão os itens do relatório.", mode: .meeting,
            speakerCertain: true, now: now, lastTriggeredAt: nil, lastFingerprint: nil
        ))
        XCTAssertTrue(CoachTriggerPolicy.shouldTrigger(
            text: "Você concorda com esse plano?", mode: .meeting,
            speakerCertain: true, now: now, lastTriggeredAt: nil, lastFingerprint: nil
        ))
        XCTAssertFalse(CoachTriggerPolicy.shouldTrigger(
            text: "Você concorda com esse plano?", mode: .meeting,
            speakerCertain: true, now: now.addingTimeInterval(2), lastTriggeredAt: now,
            lastFingerprint: CoachTriggerPolicy.fingerprint("Você concorda com esse plano?")
        ))
    }

    func testRecordingOnlyModeIsTheOnlyPassiveMode() {
        XCTAssertFalse(Mode.meeting.isPassive)
        XCTAssertTrue(Mode.recording.isPassive)
    }

    func testDiagnosticsAggregateLatencyWithoutConversationContent() {
        var diagnostics = SessionDiagnostics()
        for _ in 0..<600 {
            diagnostics.record(.init(kind: .coach, name: "first_phrase", durationMs: 500))
        }
        diagnostics.record(.init(kind: .recovery, name: "stt_restarted"))
        XCTAssertEqual(diagnostics.count("first_phrase"), 600)
        XCTAssertEqual(diagnostics.averageMs("first_phrase"), 500)
        XCTAssertEqual(diagnostics.count("stt_restarted"), 1)
        XCTAssertLessThanOrEqual(diagnostics.events.count, 500)
    }

    func testDiagnosticsAggregatesSurviveArchiveRoundTrip() throws {
        var diagnostics = SessionDiagnostics()
        for value in 0..<600 {
            diagnostics.record(.init(kind: .coach, name: "first_phrase", durationMs: Int64(value)))
        }
        diagnostics.record(.init(kind: .recovery, name: "stt_restarted"))

        let decoded = try JSONDecoder().decode(
            SessionDiagnostics.self,
            from: JSONEncoder().encode(diagnostics)
        )

        XCTAssertEqual(decoded.count("first_phrase"), 600)
        XCTAssertEqual(decoded.count(kind: .recovery), 1)
        XCTAssertEqual(decoded.durationValues("first_phrase").count, 600)
    }

    func testLatencyFallbackIsVisualAndShort() {
        XCTAssertEqual(
            LatencyFallback.guide(for: "How did you ship it?", mode: .interview),
            "PLANO → AÇÃO → RESULTADO"
        )
    }
}
