import XCTest
@testable import CueMe

final class CoachModelTests: XCTestCase {
    func testFallsBackToClaudeWhenDeepSeekHasNoKey() {
        let model = CoachModel.resolved(
            preferred: .deepseekPro,
            claudeAvailable: true,
            deepSeekAvailable: false
        )
        XCTAssertEqual(model, .sonnet)
    }

    func testFallsBackToDeepSeekWhenClaudeIsMissing() {
        let model = CoachModel.resolved(
            preferred: .sonnet,
            claudeAvailable: false,
            deepSeekAvailable: true
        )
        XCTAssertEqual(model, .deepseekPro)
    }

    func testKeepsAvailablePreference() {
        XCTAssertEqual(
            CoachModel.resolved(
                preferred: .deepseekFlash,
                claudeAvailable: true,
                deepSeekAvailable: true
            ),
            .deepseekFlash
        )
    }
}
