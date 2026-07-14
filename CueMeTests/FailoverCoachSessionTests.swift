import XCTest
@testable import CueMe

final class FailoverCoachSessionTests: XCTestCase {
    func testSlowPrimaryFallsBackToSecondary() async throws {
        let primary = StubCoachSession(output: "primary", delay: .milliseconds(150))
        let secondary = StubCoachSession(output: "secondary")
        let session = FailoverCoachSession(
            primary: primary,
            secondary: secondary,
            delay: .milliseconds(10)
        )
        let result = try await session.complete("hello")
        XCTAssertEqual(result, "secondary")
        await session.shutdown()
    }

    func testFastPrimaryWins() async throws {
        let primary = StubCoachSession(output: "primary")
        let secondary = StubCoachSession(output: "secondary")
        let session = FailoverCoachSession(
            primary: primary,
            secondary: secondary,
            delay: .milliseconds(100)
        )
        let result = try await session.complete("hello")
        XCTAssertEqual(result, "primary")
        await session.shutdown()
    }
}

private actor StubCoachSession: CoachSession {
    let output: String
    let delay: Duration

    init(output: String, delay: Duration = .zero) {
        self.output = output
        self.delay = delay
    }

    func send(_ user: String) -> AsyncThrowingStream<String, Error> {
        let output = output
        let delay = delay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do { try await Task.sleep(for: delay) }
                catch { continuation.finish(); return }
                continuation.yield(output)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func complete(_ user: String) async throws -> String { output }
    func prewarm() async throws {}
    func shutdown() async {}
}
