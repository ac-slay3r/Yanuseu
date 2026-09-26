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
    var profileID: String = ProfileStore.defaultID
    var title: String
    var messages: [ChatMessage] = []
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), profileID: String = ProfileStore.defaultID, title: String,
         messages: [ChatMessage] = [], updatedAt: Date = Date()) {
        self.id = id
        self.profileID = profileID
        self.title = title
        self.messages = messages
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case id, profileID, title, messages, updatedAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        profileID = try container.decodeIfPresent(String.self, forKey: .profileID) ?? ProfileStore.defaultID
        title = try container.decode(String.self, forKey: .title)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

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
