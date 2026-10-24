import Foundation
import Security

/// deadwax's session cookie value, kept in the Keychain per server - never the password, which the
/// app doesn't store. Readable after the phone's first unlock (so a locked phone's background work
/// can send it), and never synced or backed up to another device. Signing out is a delete.
enum SessionKeychain {
    static let service = "deadwax.session"

    static func read(_ server: String) -> String? {
        var query = base(server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
              let data = found as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, for server: String) {
        delete(server)
        var item = base(server)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        _ = SecItemAdd(item as CFDictionary, nil)
    }

    static func delete(_ server: String) {
        _ = SecItemDelete(base(server) as CFDictionary)
    }

    private static func base(_ server: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: server]
    }
}
