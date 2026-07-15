import XCTest
@testable import CueMe

final class PermissionProbeTests: XCTestCase {
    func testGrantedPermissionStartsBothCaptureChannels() {
        let plan = SessionCapturePlan.resolve(
            permissionGranted: true,
            currentIdentity: "TEAM:com.feliperun.CueMe",
            lastSuccessfulIdentity: "TEAM:com.feliperun.CueMe"
        )

        XCTAssertTrue(plan.includeSystemAudio)
        XCTAssertNil(plan.diagnosis)
    }

    func testMissingPermissionStartsMicrophoneOnlyWithoutPromptingAgain() {
        let plan = SessionCapturePlan.resolve(
            permissionGranted: false,
            currentIdentity: "TEAM:com.feliperun.CueMe",
            lastSuccessfulIdentity: nil
        )

        XCTAssertFalse(plan.includeSystemAudio)
        XCTAssertEqual(plan.diagnosis, .notGranted)
    }

    func testChangedSigningIdentityStartsMicrophoneOnlyAndExplainsCause() {
        let plan = SessionCapturePlan.resolve(
            permissionGranted: false,
            currentIdentity: "adhoc:com.feliperun.CueMe:new-code-hash",
            lastSuccessfulIdentity: "TEAM:com.feliperun.CueMe"
        )

        XCTAssertFalse(plan.includeSystemAudio)
        XCTAssertEqual(plan.diagnosis, .identityChanged)
    }
}
