import XCTest
@testable import CueMe

final class SummaryLaneTests: XCTestCase {
    func testEmptyResponseDoesNotEraseSummary() async throws {
        let lane = SummaryLane(session: StubCoachSession(response: ""))
        let result = try await lane.summarize(window: [Turn(speaker: .other, text: "Uma decisão")])
        XCTAssertNil(result)
    }

    func testParsesUsefulBullets() async throws {
        let lane = SummaryLane(session: StubCoachSession(response: "- Decisão tomada\n- Próximo passo"))
        let result = try await lane.summarize(window: [Turn(speaker: .other, text: "Uma decisão")])
        XCTAssertEqual(result, ["Decisão tomada", "Próximo passo"])
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
