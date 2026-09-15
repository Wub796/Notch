import Foundation
import Security

/// A tiny wrapper over the login keychain for one-off secrets.
///
/// The Spotify `sp_dc` cookie is account access — it must not sit in a plist in
/// Application Support where any process and every backup can read it. The
/// keychain is where a session token belongs.
enum KeychainStore {
    private static let service = "com.notchapp.Notch"

    static func set(_ value: String, for account: String) {
        let data = Data(value.utf8)
        // Replace: SecItemUpdate would leave a create path to write anyway, so
        // delete-then-add is one code path for both first write and overwrite.
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
