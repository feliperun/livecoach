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

    func testLegacyRecordWithoutMemoryFieldsStillDecodes() throws {
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
        object.removeValue(forKey: "archiveFolderName")
        object.removeValue(forKey: "notes")
        object.removeValue(forKey: "takeaways")
        object.removeValue(forKey: "artifacts")
        object.removeValue(forKey: "minutes")
        object.removeValue(forKey: "participantNames")
        object.removeValue(forKey: "coachModel")
        object.removeValue(forKey: "summaryModel")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SessionRecord.self, from: legacy)

        XCTAssertFalse(decoded.archiveFolderName.isEmpty)
        XCTAssertTrue(decoded.notes.isEmpty)
        XCTAssertTrue(decoded.takeaways.isEmpty)
        XCTAssertTrue(decoded.artifacts.isEmpty)
        XCTAssertEqual(decoded.minutes, .empty)
        XCTAssertEqual(decoded.participantName(for: .self), "Você")
        XCTAssertNil(decoded.coachModel)
        XCTAssertNil(decoded.summaryModel)
    }

    func testTranscriptCorrectionPreservesOriginalAndIsCodable() throws {
        var line = TranscriptLine(speaker: .other, text: "mono rapo", isFinal: true)
        line.applyCorrection("monorepo", at: Date(timeIntervalSince1970: 2_000))
        let decoded = try JSONDecoder().decode(
            TranscriptLine.self,
            from: JSONEncoder().encode(line)
        )
        XCTAssertEqual(decoded.text, "monorepo")
        XCTAssertEqual(decoded.originalText, "mono rapo")
        XCTAssertTrue(decoded.wasEdited)
    }
}
