import Foundation
import Security

struct ProviderCredentialStore {
    private let service = Bundle.main.bundleIdentifier ?? "cool.n0thing.yanuseu"
    private let legacyAccount = "provider-api-key"

    func save(apiKey: String, profileID: String) throws {
        let key = query(account: account(for: profileID))
        let data = Data(apiKey.utf8)
        let status = SecItemCopyMatching(key as CFDictionary, nil)
        if status == errSecSuccess {
            let update = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard update == errSecSuccess else { throw KeychainError(status: update) }
            return
        }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var attributes = key
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(attributes as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    func loadAPIKey(profileID: String) throws -> String? {
        try load(account: account(for: profileID))
    }

    func containsAPIKey(profileID: String) throws -> Bool {
        var attributes = query(account: account(for: profileID))
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(attributes as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return true
    }

    func deleteAPIKey(profileID: String) throws {
        try delete(account: account(for: profileID))
    }

    // Idempotent: never overwrite an existing scoped key with the legacy key.
    // Delete the old account only after the new value was confirmed saved.
    func migrateLegacyDefault() throws {
        guard let old = try load(account: legacyAccount) else { return }
        if try loadAPIKey(profileID: ProfileStore.defaultID) == nil {
            try save(apiKey: old, profileID: ProfileStore.defaultID)
        }
        try delete(account: legacyAccount)
    }

    private func account(for profileID: String) -> String { "provider-api-key.\(profileID)" }

    private func load(account: String) throws -> String? {
        var attributes = query(account: account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: status)
        }
        return value
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Could not access the provider key in iPhone Keychain (status \(status)). Unlock this iPhone and try again." }
    }
}
