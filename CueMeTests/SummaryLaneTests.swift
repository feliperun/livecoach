import XCTest
@testable import CueMe

final class SummaryLaneTests: XCTestCase {
    func testEmptyResponseDoesNotEraseSummary() async throws {
        let lane = SummaryLane(session: StubCoachSession(response: ""))
        let result = try await lane.summarize(
            existing: .empty,
            newTurns: [Turn(speaker: .other, text: "Uma decisão")]
        )
        XCTAssertNil(result)
    }

    func testParsesStructuredMeetingMinutes() async throws {
        let response = #"{"overview":"Plano aprovado.","topics":[{"title":"Integração","summary":"Execução incremental."}]}"#
        let lane = SummaryLane(session: StubCoachSession(response: response))
        let result = try await lane.summarize(
            existing: .empty,
            newTurns: [Turn(speaker: .other, text: "Uma decisão")]
        )
        XCTAssertEqual(result?.overview, "Plano aprovado.")
        XCTAssertEqual(result?.topics.first?.title, "Integração")
        XCTAssertEqual(result?.topics.first?.summary, "Execução incremental.")
    }
}

private actor StubCoachSession: CoachSession {
    let response: String

    init(response: String) {
        self.response = response
    }

    func send(_ user: String) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(response)
            continuation.finish()
        }
    }

    func complete(_ user: String) async throws -> String { response }
    func prewarm() async throws {}
    func shutdown() async {}
}
