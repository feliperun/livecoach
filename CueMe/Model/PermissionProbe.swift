import AppKit
import CoreGraphics
import Security

enum PermissionDiagnosis: Sendable, Equatable {
    case ready, notGranted, identityChanged, captureFailed

    static func evaluate(
        preflightGranted: Bool,
        captureSucceeded: Bool,
        currentIdentity: String,
        lastSuccessfulIdentity: String?
    ) -> Self {
        if captureSucceeded { return .ready }
        if let lastSuccessfulIdentity, lastSuccessfulIdentity != currentIdentity { return .identityChanged }
        return preflightGranted ? .captureFailed : .notGranted
    }
}

struct SessionCapturePlan: Sendable, Equatable {
    let includeSystemAudio: Bool
    let diagnosis: PermissionDiagnosis?

    static func resolve(
        permissionGranted: Bool,
        currentIdentity: String,
        lastSuccessfulIdentity: String?
    ) -> Self {
        guard !permissionGranted else {
            return .init(includeSystemAudio: true, diagnosis: nil)
        }
        return .init(
            includeSystemAudio: false,
            diagnosis: PermissionDiagnosis.evaluate(
                preflightGranted: false,
                captureSucceeded: false,
                currentIdentity: currentIdentity,
                lastSuccessfulIdentity: lastSuccessfulIdentity
            )
        )
    }
}

enum ScreenCapturePermissionProbe {
    private static let identityKey = "lastSuccessfulScreenCaptureIdentity"

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Requests TCC only from an explicit setup action. Live sessions use
    /// `isGranted` and fall back to microphone-only instead of prompting.
    static func requestAccess() -> Bool { CGRequestScreenCaptureAccess() }

    static var sessionPlan: SessionCapturePlan {
        .resolve(
            permissionGranted: isGranted,
            currentIdentity: currentIdentity,
            lastSuccessfulIdentity: lastSuccessfulIdentity
        )
    }

    static var currentIdentity: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return bundleID }
        var raw: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &raw) == errSecSuccess,
              let info = raw as? [String: Any] else { return bundleID }
        let identifier = info[kSecCodeInfoIdentifier as String] as? String ?? bundleID
        if let team = info[kSecCodeInfoTeamIdentifier as String] as? String {
            return "\(team):\(identifier)"
        }
        let codeHash = (info[kSecCodeInfoUnique as String] as? Data)?
            .map { String(format: "%02x", $0) }
            .joined() ?? "unknown"
        return "adhoc:\(identifier):\(codeHash)"
    }

    static var lastSuccessfulIdentity: String? {
        UserDefaults.standard.string(forKey: identityKey)
    }

    static func markSuccess() {
        UserDefaults.standard.set(currentIdentity, forKey: identityKey)
    }

    static func markSuccess(if captureSucceeded: Bool) {
        guard captureSucceeded else { return }
        markSuccess()
    }

    static func reset() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", bundleID]
        try? process.run()
        process.waitUntilExit()
    }
}
