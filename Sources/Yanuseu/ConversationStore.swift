import Combine
import Foundation

@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var conversations: [Conversation]
    @Published private(set) var activeID: UUID
    @Published private(set) var persistenceError: String?

    private let fileURL: URL
    private let defaults: UserDefaults

    init(fileURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.fileURL = fileURL ?? Self.defaultFileURL()
        let loaded = Self.load(from: self.fileURL)
        let initial = loaded.isEmpty ? [Conversation(title: "New conversation")] : loaded
        self.conversations = initial.sorted { $0.updatedAt > $1.updatedAt }
        let savedID = defaults.string(forKey: "conversation.activeID").flatMap(UUID.init(uuidString:))
        self.activeID = savedID.flatMap { id in initial.contains(where: { $0.id == id }) ? id : nil } ?? initial[0].id
        if loaded.isEmpty { persist() }
    }

    var activeConversation: Conversation {
        conversations.first(where: { $0.id == activeID }) ?? Conversation(title: "New conversation")
    }

    func select(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        activeID = id
        defaults.set(id.uuidString, forKey: "conversation.activeID")
    }

    func newConversation() {
        let conversation = Conversation(title: "New conversation")
        conversations.insert(conversation, at: 0)
        activeID = conversation.id
        defaults.set(conversation.id.uuidString, forKey: "conversation.activeID")
        persist()
    }

    func append(_ message: ChatMessage) {
        guard let index = conversations.firstIndex(where: { $0.id == activeID }) else { return }
        conversations[index].append(message)
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func rename(_ id: UUID, to title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        conversations[index].title = String(cleaned.prefix(80))
        persist()
    }

    func deleteAll() {
        let replacement = Conversation(title: "New conversation")
        conversations = [replacement]
        activeID = replacement.id
        defaults.set(replacement.id.uuidString, forKey: "conversation.activeID")
        persist()
    }

    func clearActiveConversation() {
        guard let index = conversations.firstIndex(where: { $0.id == activeID }) else { return }
        conversations[index] = Conversation(id: activeID, title: "New conversation")
        persist()
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if conversations.isEmpty { conversations = [Conversation(title: "New conversation")] }
        if !conversations.contains(where: { $0.id == activeID }) {
            activeID = conversations[0].id
            defaults.set(activeID.uuidString, forKey: "conversation.activeID")
        }
        persist()
    }

    private func persist() {
        do {
            let parent = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            var protectedDirectory = parent
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            try protectedDirectory.setResourceValues(directoryValues)
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            persistenceError = nil
        } catch {
            persistenceError = "Could not save conversation history on this iPhone."
        }
    }

    private static func load(from url: URL) -> [Conversation] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Conversation].self, from: data) else { return [] }
        return decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func defaultFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Yanuseu", isDirectory: true).appendingPathComponent("conversations.json")
    }
}
