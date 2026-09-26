import XCTest
@testable import Yanuseu

final class ProfileCredentialTests: XCTestCase {
    private final class MemoryBackend: CredentialBackend {
        var values: [String: String] = [:]
        var failure: Error?
        func read(account: String) throws -> String? {
            if let failure { throw failure }
            return values[account]
        }
        func write(account: String, value: String) throws {
            if let failure { throw failure }
            values[account] = value
        }
        func delete(account: String) throws {
            if let failure { throw failure }
            values.removeValue(forKey: account)
        }
    }

    private enum Locked: Error { case unavailable }

    func testKeysAreReplacedDeletedAndIsolatedByProfile() throws {
        let backend = MemoryBackend()
        let credentials = ProviderCredentialStore(backend: backend)
        try credentials.save(apiKey: "first", profileID: "a")
        try credentials.save(apiKey: "other", profileID: "b")
        try credentials.save(apiKey: "replacement", profileID: "a")
        XCTAssertEqual(try credentials.loadAPIKey(profileID: "a"), "replacement")
        XCTAssertEqual(try credentials.loadAPIKey(profileID: "b"), "other")
        try credentials.deleteAPIKey(profileID: "a")
        XCTAssertFalse(try credentials.containsAPIKey(profileID: "a"))
        XCTAssertEqual(try credentials.loadAPIKey(profileID: "b"), "other")
    }

    func testMigrationPreservesNewDefaultKeyAndDoesNotLeakIntoOtherProfile() throws {
        let backend = MemoryBackend()
        backend.values["provider-api-key"] = "legacy"
        let credentials = ProviderCredentialStore(backend: backend)
        try credentials.migrateLegacyDefault()
        XCTAssertEqual(try credentials.loadAPIKey(profileID: ProfileStore.defaultID), "legacy")
        XCTAssertNil(try credentials.loadAPIKey(profileID: "other"))
        XCTAssertNil(backend.values["provider-api-key"])
        backend.values["provider-api-key"] = "stale"
        try credentials.migrateLegacyDefault()
        XCTAssertEqual(try credentials.loadAPIKey(profileID: ProfileStore.defaultID), "legacy")
    }

    func testUnavailableKeychainIsAnErrorNotMissingCredential() throws {
        let backend = MemoryBackend()
        let credentials = ProviderCredentialStore(backend: backend)
        backend.failure = Locked.unavailable
        XCTAssertThrowsError(try credentials.containsAPIKey(profileID: "a"))
        XCTAssertThrowsError(try credentials.loadAPIKey(profileID: "a"))
        XCTAssertThrowsError(try credentials.save(apiKey: "secret", profileID: "a"))
        XCTAssertThrowsError(try credentials.deleteAPIKey(profileID: "a"))
        XCTAssertThrowsError(try credentials.migrateLegacyDefault())
        XCTAssertTrue(backend.values.isEmpty)
    }
}
