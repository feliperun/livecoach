import Foundation
import Security

/// Deepgram API key stored in the macOS Keychain. The environment fallback is
/// intended for local integration tests and CI only.
enum DeepgramCredential {
    private static let service = "CueMe.deepgram"
    private static let account = "apiKey"

    static var apiKey: String? {
        if let environment = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"],
           !environment.isEmpty {
            return environment
        }
        return keychainRead()
    }

    static var isConfigured: Bool { !(apiKey ?? "").isEmpty }

    static func setAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { keychainDelete() } else { keychainWrite(trimmed) }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func keychainRead() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    private static func keychainWrite(_ key: String) {
        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = Data(key.utf8)
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func keychainDelete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
