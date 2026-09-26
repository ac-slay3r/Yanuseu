import Combine
import Foundation

@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var conversations: [Conversation]
    @Published private(set) var activeID: UUID
    @Published private(set) var selectedProfileID: String
    @Published private(set) var persistenceError: String?

    private let fileURL: URL
    private let defaults: UserDefaults

    init(fileURL: URL? = nil, defaults: UserDefaults = .standard, profileID: String = ProfileStore.defaultID) {
        self.defaults = defaults
        self.selectedProfileID = profileID
        self.fileURL = fileURL ?? Self.defaultFileURL()
        let loaded = Self.load(from: self.fileURL)
        let initial = loaded.isEmpty ? [Conversation(profileID: profileID, title: "New conversation")] : loaded
        self.conversations = initial.sorted { $0.updatedAt > $1.updatedAt }
        let activeForProfile = initial.filter { $0.profileID == profileID }
        let savedID = (defaults.string(forKey: "conversation.activeID.\(profileID)") ??
                       (profileID == ProfileStore.defaultID ? defaults.string(forKey: "conversation.activeID") : nil))
            .flatMap(UUID.init(uuidString:))
        self.activeID = savedID.flatMap { id in activeForProfile.contains(where: { $0.id == id }) ? id : nil }
            ?? activeForProfile.first?.id ?? UUID()
        if activeForProfile.isEmpty {
            let replacement = Conversation(id: activeID, profileID: profileID, title: "New conversation")
            conversations.insert(replacement, at: 0)
            persist()
        } else if loaded.isEmpty { persist() }
    }

    var visibleConversations: [Conversation] { conversations.filter { $0.profileID == selectedProfileID } }

    var activeConversation: Conversation {
        visibleConversations.first(where: { $0.id == activeID }) ?? Conversation(id: activeID, profileID: selectedProfileID, title: "New conversation")
    }

    func switchProfile(_ profileID: String) {
        guard profileID != selectedProfileID else { return }
        selectedProfileID = profileID
        if let saved = defaults.string(forKey: "conversation.activeID.\(profileID)").flatMap(UUID.init(uuidString:)),
           visibleConversations.contains(where: { $0.id == saved }) {
            activeID = saved
        } else if let first = visibleConversations.first {
            activeID = first.id
        } else {
            let replacement = Conversation(profileID: profileID, title: "New conversation")
            conversations.insert(replacement, at: 0)
            activeID = replacement.id
            persist()
        }
        defaults.set(activeID.uuidString, forKey: "conversation.activeID.\(profileID)")
    }

    func select(_ id: UUID) {
        guard visibleConversations.contains(where: { $0.id == id }) else { return }
        activeID = id
        defaults.set(id.uuidString, forKey: "conversation.activeID.\(selectedProfileID)")
    }

    func newConversation() {
        let conversation = Conversation(profileID: selectedProfileID, title: "New conversation")
        conversations.insert(conversation, at: 0)
        activeID = conversation.id
        defaults.set(conversation.id.uuidString, forKey: "conversation.activeID.\(selectedProfileID)")
        persist()
    }

    func append(_ message: ChatMessage) {
        guard let index = conversations.firstIndex(where: { $0.id == activeID }) else { return }
        conversations[index].append(message)
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func rename(_ id: UUID, to title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id && $0.profileID == selectedProfileID }) else { return }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        conversations[index].title = String(cleaned.prefix(80))
        persist()
    }

    func deleteAll() {
        conversations.removeAll { $0.profileID == selectedProfileID }
        let replacement = Conversation(profileID: selectedProfileID, title: "New conversation")
        conversations.insert(replacement, at: 0)
        activeID = replacement.id
        defaults.set(activeID.uuidString, forKey: "conversation.activeID.\(selectedProfileID)")
        persist()
    }

    func clearActiveConversation() {
        guard let index = conversations.firstIndex(where: { $0.id == activeID && $0.profileID == selectedProfileID }) else { return }
        conversations[index] = Conversation(id: activeID, profileID: selectedProfileID, title: "New conversation")
        persist()
    }

    func delete(_ id: UUID) {
        guard visibleConversations.contains(where: { $0.id == id }) else { return }
        conversations.removeAll { $0.id == id }
        if visibleConversations.isEmpty { conversations.insert(Conversation(profileID: selectedProfileID, title: "New conversation"), at: 0) }
        if !visibleConversations.contains(where: { $0.id == activeID }) {
            activeID = visibleConversations[0].id
            defaults.set(activeID.uuidString, forKey: "conversation.activeID.\(selectedProfileID)")
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
