import XCTest
@testable import CueMe

final class TranscriptBusTests: XCTestCase {
    func testRemovesTurnLaterConfirmedAsEcho() async {
        let bus = TranscriptBus()
        let echoed = TranscriptEvent(
            speaker: .self,
            text: "Ainda a expectativa",
            isFinal: true,
            isEndOfTurn: true
        )

        await bus.publish(echoed)
        await bus.removeTurn(id: echoed.id)

        let window = await bus.window()
        XCTAssertTrue(window.isEmpty)
    }
}
