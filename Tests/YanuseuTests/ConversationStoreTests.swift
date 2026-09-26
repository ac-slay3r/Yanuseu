import XCTest
@testable import Yanuseu

@MainActor
final class ConversationStoreTests: XCTestCase {
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
        store.append(ChatMessage(role: .user, content: "Remember this locally"))
        let conversationID = store.activeID
        let restored = ConversationStore(fileURL: file, defaults: defaults)

        XCTAssertEqual(restored.activeID, conversationID)
        XCTAssertEqual(restored.activeConversation.messages.map(\.content), ["Remember this locally"])
        restored.delete(conversationID)
        XCTAssertTrue(restored.activeConversation.messages.isEmpty)
    }
}
