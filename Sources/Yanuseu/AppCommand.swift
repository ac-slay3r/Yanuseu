import Foundation

enum AppCommand: Equatable {
    case help
    case newConversation
    case clearConversation
    case tools
    case settings
    case unknown(String)

    static func parse(_ input: String) -> AppCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let parts = trimmed.split(whereSeparator: \.isWhitespace)
        let token = parts.first.map(String.init)?.lowercased() ?? trimmed.lowercased()
        guard parts.count == 1 else { return .unknown(token) }
        switch token {
        case "/help": return .help
        case "/new": return .newConversation
        case "/clear": return .clearConversation
        case "/tools": return .tools
        case "/settings": return .settings
        default: return .unknown(token)
        }
    }
}
