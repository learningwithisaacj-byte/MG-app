import Foundation
import MGKit
import Security

/// Small wrapper over the iOS Keychain. Items stay on this iPhone (ThisDeviceOnly: not in iCloud backups or
/// transferred to a new phone) and are readable after first unlock, so background checks can use them.
enum Keychain {
    private static let service = "mgev"

    static func set(_ value: Data?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var add = base
        add[kSecValueData as String] = value
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func setCodable<T: Encodable>(_ value: T?, for key: String) {
        set(value.flatMap { try? JSONEncoder().encode($0) }, for: key)
    }

    static func getCodable<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        get(key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    static func removeAll() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

/// The MG login, the session and the control PIN's hash, all in the Keychain.
/// The PIN itself is never stored: only the hash MG checks against.
final class SecureStore: SessionStore, @unchecked Sendable {
    static let shared = SecureStore()

    private struct StoredCredentials: Codable { let phone: String; let password: String }

    func load() -> MGSession? { Keychain.getCodable(MGSession.self, "session") }
    func save(_ session: MGSession?) { Keychain.setCodable(session, for: "session") }

    var credentials: Credentials? {
        get { Keychain.getCodable(StoredCredentials.self, "credentials").map { Credentials(phone: $0.phone, password: $0.password) } }
        set { Keychain.setCodable(newValue.map { StoredCredentials(phone: $0.phone, password: $0.password) }, for: "credentials") }
    }

    var pinHash: String? {
        get { Keychain.get("pinHash").map { String(decoding: $0, as: UTF8.self) } }
        set { Keychain.set(newValue.map { Data($0.utf8) }, for: "pinHash") }
    }

    func clear() { Keychain.removeAll() }
}
