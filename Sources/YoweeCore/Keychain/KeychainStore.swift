import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .saveFailed(status): "Keychain save failed with status \(status)"
        }
    }
}

public enum KeychainStore {
    public static func save(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        // Create an open-access ACL so the item is readable by any build of this app,
        // regardless of ad-hoc code signature changes between rebuilds during development.
        var access: SecAccess?
        SecAccessCreate("yowee \(key)" as CFString, nil, &access)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "yowee",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        if let access { query[kSecAttrAccess as String] = access }
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    public static func load(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "yowee",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "yowee",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
