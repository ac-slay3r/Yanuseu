import Foundation

struct ToolCall: Identifiable, Codable, Equatable {
    struct Function: Codable, Equatable {
        var name: String
        var arguments: String
    }

    var id: String
    var type: String = "function"
    var function: Function
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
        case tool
    }

    var id: UUID = UUID()
    var role: Role
    var content: String
    var createdAt: Date = Date()
    var toolCallID: String? = nil
    var toolName: String? = nil
    var toolCalls: [ToolCall]? = nil
}

struct Conversation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var messages: [ChatMessage] = []
    var updatedAt: Date = Date()

    mutating func append(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = message.createdAt
        if title == "New conversation", message.role == .user {
            title = String(message.content.prefix(48))
        }
    }
}

enum ConversationExporter {
    static func text(for conversation: Conversation) -> String {
        var lines = ["# \(conversation.title)"]
        guard !conversation.messages.isEmpty else {
            lines.append("")
            lines.append("No messages in this conversation.")
            return lines.joined(separator: "\n")
        }

        for message in conversation.messages {
            let label: String
            switch message.role {
            case .user:
                label = "User"
            case .assistant:
                label = "Yanuseu"
            case .tool:
                label = "Tool result (\(message.toolName ?? "unknown"))"
            }
            lines.append("")
            lines.append("\(label): \(message.content)")
            if let calls = message.toolCalls, !calls.isEmpty {
                for call in calls {
                    lines.append("Tool request (\(call.function.name)): \(call.function.arguments)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
