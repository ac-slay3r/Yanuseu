import Foundation
import Security

protocol CredentialBackend {
    func read(account: String) throws -> String?
    func write(account: String, value: String) throws
    func delete(account: String) throws
}

struct KeychainCredentialBackend: CredentialBackend {
    private let service = Bundle.main.bundleIdentifier ?? "cool.n0thing.yanuseu"

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read(account: String) throws -> String? {
        var attributes = query(account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return value
    }

    func write(account: String, value: String) throws {
        let data = Data(value.utf8)
        var attributes = query(account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess { return }
        guard status == errSecDuplicateItem else { throw KeychainError(status: status) }
        let update = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard update == errSecSuccess else { throw KeychainError(status: update) }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "iPhone Keychain is unavailable (status \(status)). Unlock the device and retry." }
    }
}

struct ProviderCredentialStore {
    private let backend: any CredentialBackend
    private let legacyAccount = "provider-api-key"
    init(backend: any CredentialBackend = KeychainCredentialBackend()) { self.backend = backend }

    private func account(_ profileID: String) -> String { "provider-api-key.\(profileID)" }
    func save(apiKey: String, profileID: String) throws { try backend.write(account: account(profileID), value: apiKey) }
    func loadAPIKey(profileID: String) throws -> String? { try backend.read(account: account(profileID)) }
    func deleteAPIKey(profileID: String) throws { try backend.delete(account: account(profileID)) }
    func containsAPIKey(profileID: String) throws -> Bool { try loadAPIKey(profileID: profileID) != nil }

    func migrateLegacyDefault() throws {
        guard let old = try backend.read(account: legacyAccount) else { return }
        if try loadAPIKey(profileID: ProfileStore.defaultID) == nil {
            try save(apiKey: old, profileID: ProfileStore.defaultID)
        }
        try backend.delete(account: legacyAccount)
    }
}
