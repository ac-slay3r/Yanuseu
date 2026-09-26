import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    var id: UUID = UUID()
    var role: Role
    var content: String
    var createdAt: Date = Date()
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
