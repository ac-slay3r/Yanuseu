import Foundation

struct CommandEntry: Identifiable {
    let name: String
    let summary: String
    let command: AppCommand
    var id: String { name }
}

enum AppCommand: Equatable {
    case help
    case newConversation
    case clearConversation
    case tools
    case settings
    case skills
    case memory
    case unknown(String)

    static let registry: [CommandEntry] = [
        .init(name: "/help", summary: "List available native commands", command: .help),
        .init(name: "/new", summary: "Start a new conversation", command: .newConversation),
        .init(name: "/clear", summary: "Clear this conversation after confirmation", command: .clearConversation),
        .init(name: "/tools", summary: "Control local tool permissions", command: .tools),
        .init(name: "/settings", summary: "Open provider and agent settings", command: .settings),
        .init(name: "/skills", summary: "Inspect and enable local skill instructions", command: .skills),
        .init(name: "/memory", summary: "Inspect and correct local memory", command: .memory)
    ]

    static var helpText: String {
        "Native commands:\n" + registry.map { "\($0.name) — \($0.summary)" }.joined(separator: "\n")
    }

    static func suggestions(for input: String) -> [CommandEntry] {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("/"), !text.contains(where: \.isWhitespace) else { return [] }
        return registry.filter { $0.name.hasPrefix(text.lowercased()) }
    }

    static func parse(_ input: String) -> AppCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let parts = trimmed.split(whereSeparator: \.isWhitespace)
        let token = parts.first.map(String.init)?.lowercased() ?? trimmed.lowercased()
        guard parts.count == 1 else { return .unknown(token) }
        return registry.first { $0.name == token }?.command ?? .unknown(token)
    }
}
