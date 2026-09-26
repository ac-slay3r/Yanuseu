import XCTest
@testable import Yanuseu

@MainActor
final class ConversationStoreTests: XCTestCase {
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
