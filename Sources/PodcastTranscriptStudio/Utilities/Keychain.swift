import Foundation
import Security

/// Stores LLM API keys in the macOS Keychain — never in SQLite (PRD-FEAT-008 / PRD-SEC-007).
/// Values are keyed by an opaque reference string that *is* what gets stored in the DB.
enum Keychain {
    private static let service = "app.podcasttranscriptstudio.apikeys"

    static func set(_ value: String, ref: String) {
        let account = ref
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(ref: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(ref: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref
        ]
        SecItemDelete(query as CFDictionary)
    }
}
