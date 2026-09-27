import XCTest
@testable import Yanuseu

@MainActor
final class ProfileStoreTests: XCTestCase {
    private func isolatedDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "YanuseuProfilesTests-\(UUID().uuidString)"))
    }

    func testLegacySettingsBecomeDefaultAndNeverSerializeSecret() throws {
        let defaults = try isolatedDefaults()
        defer { if let name = defaults.volatileDomainNames.first(where: { $0.hasPrefix("YanuseuProfilesTests-") }) { defaults.removePersistentDomain(forName: name) } }
        defaults.set("https://example.com/v1", forKey: "provider.baseURL")
        defaults.set("legacy-model", forKey: "provider.model")
        defaults.set("Legacy instruction", forKey: "agent.instructions")
        defaults.set(true, forKey: "agent.calculator.enabled")
        let store = ProfileStore(defaults: defaults)
        XCTAssertEqual(store.selected.id, ProfileStore.defaultID)
        XCTAssertEqual(store.selected.model, "legacy-model")
        XCTAssertEqual(store.selected.instructions, "Legacy instruction")
        XCTAssertTrue(store.selected.calculatorEnabled)
        let stored = try XCTUnwrap(defaults.data(forKey: ProfileStore.storageKey))
        XCTAssertFalse(String(decoding: stored, as: UTF8.self).contains("api-key"))
        XCTAssertEqual(ProfileStore(defaults: defaults).selected.model, "legacy-model")
    }

    func testUnreadableProfilesCannotBeSilentlyReplacedAndRequireExplicitArchive() throws {
        let defaults = try isolatedDefaults()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Data("damaged profile index".utf8)
        defaults.set(original, forKey: ProfileStore.storageKey)
        let blocked = ProfileStore(defaults: defaults, archiveDirectory: directory)
        XCTAssertNotNil(blocked.storageError)
        blocked.create(name: "Should not save")
        XCTAssertEqual(defaults.data(forKey: ProfileStore.storageKey), original)
        let archive = try blocked.archiveUnreadableProfilesAndReset()
        XCTAssertEqual(try Data(contentsOf: archive), original)
        XCTAssertEqual(ProfileStore(defaults: defaults, archiveDirectory: directory).archivedProfilesURLs, [archive])
        XCTAssertNil(blocked.storageError)
        XCTAssertEqual(ProfileStore(defaults: defaults).selectedID, ProfileStore.defaultID)
    }

    func testFailedProfileArchiveKeepsOriginalPreferenceAndBlocksWrites() throws {
        let defaults = try isolatedDefaults()
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocker".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let original = Data("damaged".utf8)
        defaults.set(original, forKey: ProfileStore.storageKey)
        let store = ProfileStore(defaults: defaults, archiveDirectory: blocker.appendingPathComponent("archives"))
        XCTAssertThrowsError(try store.archiveUnreadableProfilesAndReset())
        XCTAssertNotNil(store.storageError)
        store.select(ProfileStore.defaultID)
        XCTAssertEqual(defaults.data(forKey: ProfileStore.storageKey), original)
    }

    func testCreateSelectUpdateAndReloadAreIsolated() throws {
        let defaults = try isolatedDefaults()
        let store = ProfileStore(defaults: defaults)
        let original = store.selected
        let second = store.create(name: "Work")
        XCTAssertNotEqual(second.id, original.id)
        store.updateSelected(baseURL: "https://work.example/v1", model: "work-model", instructions: "Work only", calculatorEnabled: true)
        store.select(original.id)
        XCTAssertEqual(store.selected.model, original.model)
        XCTAssertEqual(store.selected.instructions, original.instructions)
        XCTAssertFalse(store.selected.calculatorEnabled)
        store.select(second.id)
        XCTAssertEqual(store.selected.model, "work-model")
        XCTAssertEqual(ProfileStore(defaults: defaults).selected.id, second.id)
    }

    func testDraftsStayMemoryOnlyAndNeverCrossProfiles() throws {
        let defaults = try isolatedDefaults()
        let store = ProfileStore(defaults: defaults)
        let first = store.selectedID
        store.saveDraft("Private draft", for: first)
        let second = store.create(name: "Other")
        XCTAssertEqual(store.draft(for: second.id), "")
        store.saveDraft("Other draft", for: second.id)
        XCTAssertEqual(store.draft(for: first), "Private draft")
        XCTAssertEqual(ProfileStore(defaults: defaults).draft(for: first), "")
    }

    func testSessionHistoryDoesNotCrossSelectedProfilesAndLegacyRemainsDefault() throws {
        let defaults = try isolatedDefaults()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("conversations.json")
        let store = ConversationStore(fileURL: file, defaults: defaults)
        store.append(ChatMessage(role: .user, content: "Original"))
        let originalID = store.activeID
        store.switchProfile("work")
        XCTAssertTrue(store.activeConversation.messages.isEmpty)
        XCTAssertTrue(store.visibleConversations.allSatisfy { $0.profileID == "work" })
        store.append(ChatMessage(role: .user, content: "Work only"))
        let workID = store.activeID
        store.select(originalID)
        XCTAssertEqual(store.activeID, workID)
        store.switchProfile(ProfileStore.defaultID)
        XCTAssertEqual(store.activeID, originalID)
        XCTAssertEqual(store.activeConversation.messages.map(\.content), ["Original"])
        XCTAssertEqual(ConversationStore(fileURL: file, defaults: defaults, profileID: "work").activeConversation.messages.map(\.content), ["Work only"])
    }
}
