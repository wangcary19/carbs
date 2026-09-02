// carbs — Keychain storage for the Electricity Maps token

import Foundation
import Security

/// The token lives in the login Keychain as a generic password (this device only,
/// no iCloud sync) instead of plaintext config.json. Falls back to the 0600-permission
/// config file only when the Keychain is unavailable (e.g. some unsigned dev runs).
enum Keychain {
    private static let service = "app.carbs.menubar"
    private static let account = "electricitymaps-token"

    static func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return token
    }

    /// Empty string deletes the item. Returns false when the Keychain is unusable.
    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if token.isEmpty {
            SecItemDelete(base as CFDictionary)
            return true
        }
        var attrs = base
        attrs[kSecValueData as String] = Data(token.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem {
            return SecItemUpdate(base as CFDictionary,
                                 [kSecValueData as String: Data(token.utf8)] as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }
}
