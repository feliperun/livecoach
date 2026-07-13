import Foundation
import Security

/// Credenciais da API DeepSeek. A API key vive no Keychain do macOS (nunca em
/// disco claro nem no brief.json). O endpoint base é configurável (default: o
/// oficial OpenAI-compatível) e guardado em `UserDefaults` por não ser segredo.
///
/// Fallback de `DEEPSEEK_API_KEY` no ambiente para rodar via Xcode/terminal sem
/// precisar preencher a UI.
enum DeepSeekCredential {
    static let defaultBaseURL = "https://api.deepseek.com/v1"

    private static let service = "CueMe.deepseek"
    private static let account = "apiKey"
    private static let baseURLKey = "deepseek.baseURL"

    // MARK: - API key (Keychain)

    static var apiKey: String? {
        if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"],
           !env.isEmpty {
            return env
        }
        return keychainRead()
    }

    static var isConfigured: Bool { !(apiKey ?? "").isEmpty }

    /// Grava (ou apaga, se vazia) a API key no Keychain.
    static func setAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keychainDelete()
        } else {
            keychainWrite(trimmed)
        }
    }

    // MARK: - Base URL (UserDefaults)

    static var baseURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: baseURLKey) ?? ""
            return stored.isEmpty ? defaultBaseURL : stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed, forKey: baseURLKey)
        }
    }

    // MARK: - Keychain primitives

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func keychainRead() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    private static func keychainWrite(_ token: String) {
        let data = Data(token.utf8)
        let query = baseQuery()
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func keychainDelete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
