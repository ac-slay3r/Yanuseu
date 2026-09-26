import Foundation
import Security

struct ProviderCredentialStore {
    private let service = Bundle.main.bundleIdentifier ?? "cool.n0thing.yanuseu"
    private let account = "provider-api-key"

    func save(apiKey: String) throws {
        let key = query
        let data = Data(apiKey.utf8)
        let status = SecItemCopyMatching(key as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError(status: updateStatus) }
            return
        }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var attributes = key
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func loadAPIKey() -> String? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    func containsAPIKey() -> Bool {
        var attributes = query
        attributes[kSecReturnData as String] = false
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(attributes as CFDictionary, nil) == errSecSuccess
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Could not save the API key to iPhone Keychain (status \(status))." }
    }
}
