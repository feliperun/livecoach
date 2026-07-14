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

enum ScreenCapturePermissionProbe {
    private static let identityKey = "lastSuccessfulScreenCaptureIdentity"

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    static var currentIdentity: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return bundleID }
        var raw: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &raw) == errSecSuccess,
              let info = raw as? [String: Any] else { return bundleID }
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String ?? "adhoc"
        let identifier = info[kSecCodeInfoIdentifier as String] as? String ?? bundleID
        return "\(team):\(identifier)"
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
