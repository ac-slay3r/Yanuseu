import XCTest
@testable import Yanuseu

final class ConversationExportTests: XCTestCase {
    func testExportIncludesTitleMessagesAndRoleLabels() {
        let conversation = Conversation(
            title: "Trip planning",
            messages: [
                ChatMessage(role: .user, content: "Find a quiet place"),
                ChatMessage(role: .assistant, content: "I can help brainstorm options.")
            ]
        )

        let exported = ConversationExporter.text(for: conversation)
        XCTAssertTrue(exported.contains("# Trip planning"))
        XCTAssertTrue(exported.contains("User: Find a quiet place"))
        XCTAssertTrue(exported.contains("Yanuseu: I can help brainstorm options."))
    }

    func testExportMarksToolMessages() {
        let conversation = Conversation(
            title: "Calculator",
            messages: [ChatMessage(role: .tool, content: "14", toolName: "calculator")]
        )

        let exported = ConversationExporter.text(for: conversation)
        XCTAssertTrue(exported.contains("Tool result (calculator): 14"))
    }

    func testEmptyConversationExportsAnExplicitEmptyState() {
        let exported = ConversationExporter.text(for: Conversation(title: "Empty"))
        XCTAssertTrue(exported.contains("# Empty"))
        XCTAssertTrue(exported.contains("No messages in this conversation."))
    }
}
