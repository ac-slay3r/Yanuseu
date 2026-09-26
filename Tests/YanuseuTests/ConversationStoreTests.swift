import XCTest
@testable import Yanuseu

@MainActor
final class ConversationStoreTests: XCTestCase {
    func testProfilesCannotSelectOrClearEachOthersSessions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("history.json")
        let suite = "YanuseuTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = ConversationStore(fileURL: file, defaults: defaults)
        store.append(ChatMessage(role: .user, content: "Default only"))
        let first = store.activeID
        store.switchProfile("another-profile")
        XCTAssertTrue(store.visibleConversations.allSatisfy { $0.profileID == "another-profile" })
        store.select(first)
        XCTAssertNotEqual(store.activeID, first)
        store.append(ChatMessage(role: .user, content: "Other only"))
        store.deleteAll()
        store.switchProfile(ProfileStore.defaultID)
        XCTAssertEqual(store.activeID, first)
        XCTAssertEqual(store.activeConversation.messages.map(\.content), ["Default only"])
        let restored = ConversationStore(fileURL: file, defaults: defaults, profileID: "another-profile")
        XCTAssertTrue(restored.visibleConversations.allSatisfy { $0.profileID == "another-profile" })
        XCTAssertTrue(restored.activeConversation.messages.isEmpty)
    }

    func testLegacyConversationDecodesIntoDefaultProfile() throws {
        let message = ChatMessage(role: .user, content: "Legacy")
        let encoded = try JSONEncoder().encode(Conversation(title: "Old", messages: [message]))
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        dictionary.removeValue(forKey: "profileID")
        let legacy = try JSONSerialization.data(withJSONObject: dictionary)
        XCTAssertEqual(try JSONDecoder().decode(Conversation.self, from: legacy).profileID, ProfileStore.defaultID)
    }

    func testClearingActiveConversationPreservesOtherConversations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("history.json")
        let suite = "YanuseuTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }

        let store = ConversationStore(fileURL: file, defaults: defaults)
        store.append(ChatMessage(role: .user, content: "Keep this older conversation"))
        let olderID = store.activeID
        store.newConversation()
        store.append(ChatMessage(role: .user, content: "Clear only this one"))
        let activeID = store.activeID

        store.clearActiveConversation()

        XCTAssertEqual(store.activeID, activeID)
        XCTAssertTrue(store.activeConversation.messages.isEmpty)
        XCTAssertEqual(store.conversations.first(where: { $0.id == olderID })?.messages.map(\.content), ["Keep this older conversation"])
    }

    func testConversationSurvivesStoreReloadAndCanBeDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("history.json")
        let suite = "YanuseuTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }

        let store = ConversationStore(fileURL: file, defaults: defaults)
        let directoryValues = try XCTUnwrap(try? file.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]))
        XCTAssertEqual(directoryValues.isExcludedFromBackup, true)
        store.append(ChatMessage(role: .user, content: "Remember this locally"))
        let conversationID = store.activeID
        let restored = ConversationStore(fileURL: file, defaults: defaults)

        XCTAssertEqual(restored.activeID, conversationID)
        XCTAssertEqual(restored.activeConversation.messages.map(\.content), ["Remember this locally"])
        restored.deleteAll()
        let cleared = ConversationStore(fileURL: file, defaults: defaults)
        XCTAssertTrue(cleared.activeConversation.messages.isEmpty)
        XCTAssertEqual(cleared.conversations.count, 1)
    }
}
