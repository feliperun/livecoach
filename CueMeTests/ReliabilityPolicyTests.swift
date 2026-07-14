import XCTest
@testable import CueMe

final class ReliabilityPolicyTests: XCTestCase {
    func testWatchdogRestartsOnlyStalledChannel() {
        let now = Date()
        var watchdog = RuntimeWatchdog(startedAt: now.addingTimeInterval(-10))
        watchdog.observeChunk(.self, at: now.addingTimeInterval(-10))
        watchdog.observeChunk(.other, at: now)
        XCTAssertEqual(
            watchdog.evaluate(now: now, micState: .active, systemState: .active, recordingFrames: nil),
            [.restartMicrophone]
        )
    }

    func testWatchdogRestartsSTTAfterRecentVoiceWithoutTranscript() {
        let now = Date()
        var watchdog = RuntimeWatchdog(startedAt: now.addingTimeInterval(-20))
        watchdog.observeLevel(.other, level: 0.5, at: now.addingTimeInterval(-7))
        watchdog.observeTranscript(.other, at: now.addingTimeInterval(-20))
        XCTAssertTrue(
            watchdog.evaluate(now: now, micState: .waiting, systemState: .waiting, recordingFrames: nil)
                .contains(.restartSTT(.other))
        )
    }

    func testAdaptiveTriggerRejectsUncertainStatement() {
        XCTAssertFalse(AdaptiveCoachTrigger.shouldTrigger(
            text: "I led the migration with my team",
            speakerCertain: false,
            stablePartial: true
        ))
        XCTAssertTrue(AdaptiveCoachTrigger.shouldTrigger(
            text: "How did you lead the migration with your team?",
            speakerCertain: true,
            stablePartial: true
        ))
    }

    func testPerformanceReportCalculatesCoverageAndP95() {
        var diagnostics = SessionDiagnostics()
        for _ in 0..<4 { diagnostics.record(.init(kind: .coach, name: "requested")) }
        for latency in [500, 700, 900] as [Int64] {
            diagnostics.record(.init(kind: .coach, name: "completed"))
            diagnostics.record(.init(kind: .coach, name: "first_phrase", durationMs: latency))
        }
        diagnostics.record(.init(kind: .recovery, name: "stt_restarted"))
        let report = SessionPerformanceReport(diagnostics: diagnostics)
        XCTAssertEqual(report.coveragePercent, 75)
        XCTAssertEqual(report.firstPhraseP50Ms, 700)
        XCTAssertEqual(report.firstPhraseP95Ms, 900)
        XCTAssertEqual(report.recoveries, 1)
    }

    func testPermissionDiagnosisDetectsChangedIdentity() {
        XCTAssertEqual(
            PermissionDiagnosis.evaluate(
                preflightGranted: true,
                captureSucceeded: false,
                currentIdentity: "TEAM:new",
                lastSuccessfulIdentity: "TEAM:old"
            ),
            .identityChanged
        )
    }

    func testVirtualSixtyMinuteSoakStaysHealthyAndDetectsInjectedFailures() {
        let start = Date(timeIntervalSince1970: 1_000)
        var watchdog = RuntimeWatchdog(startedAt: start)
        var frames: Int64 = 0

        for tick in 0..<(60 * 30) { // 60 minutes, one tick every two seconds
            let now = start.addingTimeInterval(Double(tick * 2))
            frames += 32_000
            watchdog.observeChunk(.self, at: now)
            watchdog.observeChunk(.other, at: now)
            if tick.isMultiple(of: 5) {
                watchdog.observeLevel(.self, level: 0.3, at: now)
                watchdog.observeLevel(.other, level: 0.3, at: now)
                watchdog.observeTranscript(.self, at: now)
                watchdog.observeTranscript(.other, at: now)
            }
            XCTAssertTrue(
                watchdog.evaluate(
                    now: now,
                    micState: .active,
                    systemState: .active,
                    recordingFrames: frames
                ).isEmpty
            )
        }

        let stalledAt = start.addingTimeInterval(3_606)
        watchdog.observeChunk(.self, at: stalledAt)
        XCTAssertTrue(
            watchdog.evaluate(
                now: stalledAt,
                micState: .active,
                systemState: .active,
                recordingFrames: frames + 32_000
            ).contains(.restartSystemCapture)
        )

        watchdog.observeChunk(.other, at: stalledAt)
        var recorderAction = false
        for offset in stride(from: 2, through: 10, by: 2) {
            let now = stalledAt.addingTimeInterval(Double(offset))
            watchdog.observeChunk(.self, at: now)
            watchdog.observeChunk(.other, at: now)
            recorderAction = recorderAction || watchdog.evaluate(
                now: now,
                micState: .active,
                systemState: .active,
                recordingFrames: frames + 32_000
            ).contains(.recordingStalled)
        }
        XCTAssertTrue(recorderAction)
    }

}
