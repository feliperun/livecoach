import XCTest
@testable import CueMe

final class CoachConnectionPresentationTests: XCTestCase {
    func testIdleDoesNotPretendToConnect() {
        let status = CoachConnectionPresentation.resolve(
            provider: "Claude",
            state: .idle,
            ready: false
        )

        XCTAssertEqual(status.label, "Pronto para iniciar")
        XCTAssertFalse(status.showsProgress)
        XCTAssertFalse(status.isReady)
    }

    func testPreparingShowsConnectionProgress() {
        let status = CoachConnectionPresentation.resolve(
            provider: "Claude",
            state: .preparing,
            ready: false
        )

        XCTAssertEqual(status.label, "Conectando Claude…")
        XCTAssertTrue(status.showsProgress)
        XCTAssertFalse(status.isReady)
    }

    func testRunningAndReadyShowsProviderAsReady() {
        let status = CoachConnectionPresentation.resolve(
            provider: "DeepSeek",
            state: .running,
            ready: true
        )

        XCTAssertEqual(status.label, "DeepSeek pronto")
        XCTAssertFalse(status.showsProgress)
        XCTAssertTrue(status.isReady)
    }
}
