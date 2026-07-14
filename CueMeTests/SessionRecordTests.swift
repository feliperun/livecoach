import XCTest
@testable import CueMe

final class SessionRecordTests: XCTestCase {
    func testLegacyRecordFallsBackToSessionClock() throws {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let record = SessionRecord(
            startedAt: startedAt,
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            summaryBullets: []
        )

        let encoded = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "recordingStartedAt")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: legacy)

        XCTAssertEqual(decoded.audioTimelineStart, startedAt)
    }

    func testRecordingClockWinsWhenPresent() {
        let sessionStart = Date(timeIntervalSince1970: 1_000)
        let audioStart = sessionStart.addingTimeInterval(12)
        let record = SessionRecord(
            startedAt: sessionStart,
            recordingStartedAt: audioStart,
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            summaryBullets: []
        )
        XCTAssertEqual(record.audioTimelineStart, audioStart)
    }

    func testLegacyRecordWithoutDiagnosticsStillDecodes() throws {
        let record = SessionRecord(
            startedAt: Date(timeIntervalSince1970: 1_000),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            summaryBullets: []
        )
        let encoded = try JSONEncoder().encode(record)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "diagnostics")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SessionRecord.self, from: legacy)

        XCTAssertTrue(decoded.diagnostics.events.isEmpty)
    }
}
