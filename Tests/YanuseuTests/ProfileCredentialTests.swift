import XCTest
@testable import Yanuseu

final class ProfileCredentialTests: XCTestCase {
    func testKeysAreReplacedDeletedAndIsolatedByProfile() throws {
        let credentials = ProviderCredentialStore()
        let first = UUID().uuidString
        let second = UUID().uuidString
        defer {
            try? credentials.deleteAPIKey(profileID: first)
            try? credentials.deleteAPIKey(profileID: second)
        }
        try credentials.save(apiKey: "first", profileID: first)
        try credentials.save(apiKey: "second", profileID: second)
        XCTAssertEqual(try credentials.loadAPIKey(profileID: first), "first")
        XCTAssertEqual(try credentials.loadAPIKey(profileID: second), "second")
        try credentials.save(apiKey: "replacement", profileID: first)
        XCTAssertEqual(try credentials.loadAPIKey(profileID: first), "replacement")
        XCTAssertEqual(try credentials.loadAPIKey(profileID: second), "second")
        try credentials.deleteAPIKey(profileID: first)
        XCTAssertNil(try credentials.loadAPIKey(profileID: first))
        XCTAssertEqual(try credentials.loadAPIKey(profileID: second), "second")
    }

    func testMissingKeyDoesNotLeakLegacyCredentialIntoAnotherProfile() throws {
        let credentials = ProviderCredentialStore()
        XCTAssertNil(try credentials.loadAPIKey(profileID: UUID().uuidString))
    }
}
