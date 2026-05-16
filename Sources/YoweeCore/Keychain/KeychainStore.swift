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

        // In DEBUG builds, create an open-access ACL so items remain readable across
        // ad-hoc re-signs (each rebuild changes the code identity under ad-hoc signing).
        // In release builds, use no explicit ACL — the signed Developer ID identity is
        // stable across releases, so the default ACL is sufficient and more secure.
        #if DEBUG
        var access: SecAccess?
        SecAccessCreate("yowee \(key)" as CFString, nil, &access)
        #endif

        // Attempt an in-place update first — avoids the delete-then-add window where a
        // crash between the two calls would permanently lose the key.
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "yowee",
        ]
        var attrs: [String: Any] = [kSecValueData as String: data]
        #if DEBUG
        if let access { attrs[kSecAttrAccess as String] = access }
        #endif
        let updateStatus = SecItemUpdate(lookup as CFDictionary, attrs as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // No existing item — add fresh.
            var addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecAttrService as String: "yowee",
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            #if DEBUG
            if let access { addQuery[kSecAttrAccess as String] = access }
            #endif
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.saveFailed(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.saveFailed(updateStatus)
        }
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
