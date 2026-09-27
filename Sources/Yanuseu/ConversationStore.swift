import Combine
import Foundation

@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var conversations: [Conversation]
    @Published private(set) var activeID: UUID
    @Published private(set) var selectedProfileID: String
    @Published private(set) var persistenceError: String?
    @Published private(set) var needsRecovery = false
    @Published private(set) var recoveredHistoryURL: URL?

    private let fileURL: URL
    private let defaults: UserDefaults
    private var pendingArchiveURL: URL?

    init(fileURL: URL? = nil, defaults: UserDefaults = .standard, profileID: String = ProfileStore.defaultID) {
        self.defaults = defaults
        self.selectedProfileID = profileID
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.recoveredHistoryURL = Self.latestArchive(beside: self.fileURL)
        let marker = Self.recoveryMarker(beside: self.fileURL)
        let missingAfterMove = !FileManager.default.fileExists(atPath: self.fileURL.path) &&
            FileManager.default.fileExists(atPath: marker.path)
        if missingAfterMove,
           let name = try? String(contentsOf: marker, encoding: .utf8),
           name.hasPrefix(self.fileURL.lastPathComponent + ".unreadable-"),
           !name.contains("/"), !name.contains("\\"),
           FileManager.default.fileExists(atPath: self.fileURL.deletingLastPathComponent().appendingPathComponent(name).path) {
            self.pendingArchiveURL = self.fileURL.deletingLastPathComponent().appendingPathComponent(name)
            self.recoveredHistoryURL = self.pendingArchiveURL
        }
        let loaded: [Conversation]
        let loadFailed: Bool
        do {
            loaded = try Self.load(from: self.fileURL)
            loadFailed = false
        } catch {
            loaded = []
            loadFailed = true
        }
        let initial = loaded.isEmpty ? [Conversation(profileID: profileID, title: "New conversation")] : loaded
        self.conversations = initial.sorted { $0.updatedAt > $1.updatedAt }
        let activeForProfile = initial.filter { $0.profileID == profileID && !$0.isArchived }
        let savedID = (defaults.string(forKey: "conversation.activeID.\(profileID)") ??
                       (profileID == ProfileStore.defaultID ? defaults.string(forKey: "conversation.activeID") : nil))
            .flatMap(UUID.init(uuidString:))
        self.activeID = savedID.flatMap { id in activeForProfile.contains(where: { $0.id == id }) ? id : nil }
            ?? activeForProfile.first?.id ?? UUID()
        if loadFailed || missingAfterMove {
            needsRecovery = true
            persistenceError = missingAfterMove
                ? "History recovery was interrupted. The archived history must be protected before starting fresh."
                : "Saved history could not be read. Nothing has been overwritten; archive it before starting fresh."
        }
        if activeForProfile.isEmpty {
            let replacement = Conversation(id: activeID, profileID: profileID, title: "New conversation")
            conversations.insert(replacement, at: 0)
            persist()
        } else if loaded.isEmpty { persist() }
        if !needsRecovery && FileManager.default.fileExists(atPath: marker.path) {
            try? FileManager.default.removeItem(at: marker)
        }
    }

    var archivedHistoryURLs: [URL] { Self.archives(beside: fileURL) }

    var visibleConversations: [Conversation] { conversations.filter { $0.profileID == selectedProfileID && !$0.isArchived } }

    var archivedConversations: [Conversation] { conversations.filter { $0.profileID == selectedProfileID && $0.isArchived } }

    func orphanedConversations(knownProfileIDs: Set<String>) -> [Conversation] {
        conversations.filter { !knownProfileIDs.contains($0.profileID) }
    }

    @discardableResult
    func recoverOrphanedConversation(_ id: UUID, knownProfileIDs: Set<String>) -> Bool {
        guard !needsRecovery, knownProfileIDs.contains(selectedProfileID),
              let index = conversations.firstIndex(where: { $0.id == id && !knownProfileIDs.contains($0.profileID) })
        else { return false }
        let previous = conversations
        conversations[index].profileID = selectedProfileID
        conversations[index].isArchived = false
        persist()
        if persistenceError != nil { conversations = previous; return false }
        return true
    }

    func search(_ query: String) -> [Conversation] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return visibleConversations }
        return visibleConversations.filter { conversation in
            conversation.title.localizedStandardContains(term) ||
            conversation.messages.contains { $0.content.localizedStandardContains(term) }
        }
    }

    /// Only called after an explicit on-screen confirmation. Preserve the original bytes.
    func archiveUnreadableHistoryAndReset(protectArchive: ((URL) throws -> Void)? = nil) throws {
        guard needsRecovery else { return }
        if pendingArchiveURL == nil {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw ConversationRecoveryError.missingArchive
            }
            let archive = fileURL.deletingLastPathComponent()
                .appendingPathComponent(fileURL.lastPathComponent + ".unreadable-" + UUID().uuidString)
            try Data(archive.lastPathComponent.utf8).write(
                to: Self.recoveryMarker(beside: fileURL), options: [.atomic, .completeFileProtection]
            )
            try FileManager.default.moveItem(at: fileURL, to: archive)
            pendingArchiveURL = archive
            recoveredHistoryURL = archive
        }
        if let archive = pendingArchiveURL {
            if let protectArchive { try protectArchive(archive) }
            else { try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: archive.path) }
        }
        needsRecovery = false
        conversations = [Conversation(profileID: selectedProfileID, title: "New conversation")]
        activeID = conversations[0].id
        persist()
        if persistenceError != nil {
            needsRecovery = true
            throw ConversationRecoveryError.couldNotSave
        }
        defaults.set(activeID.uuidString, forKey: "conversation.activeID.\(selectedProfileID)")
        try? FileManager.default.removeItem(at: Self.recoveryMarker(beside: fileURL))
    }

    enum ConversationRecoveryError: LocalizedError {
        case couldNotSave
        case missingArchive
        var errorDescription: String? {
            switch self {
            case .couldNotSave: "The original history was archived, but a new history file could not be saved."
            case .missingArchive: "The pending history archive is missing. No new history was written."
            }
        }
    }

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
        guard let index = conversations.firstIndex(where: { $0.id == id && $0.profileID == selectedProfileID }) else { return }
        if conversations[index].isArchived {
            conversations[index].isArchived = false
            persist()
        }
        activeID = id
        defaults.set(id.uuidString, forKey: "conversation.activeID.\(selectedProfileID)")
    }

    func archive(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id && $0.profileID == selectedProfileID && !$0.isArchived }) else { return }
        conversations[index].isArchived = true
        if activeID == id {
            if let next = visibleConversations.first { activeID = next.id }
            else {
                let replacement = Conversation(profileID: selectedProfileID, title: "New conversation")
                conversations.insert(replacement, at: 0)
                activeID = replacement.id
            }
            defaults.set(activeID.uuidString, forKey: "conversation.activeID.\(selectedProfileID)")
        }
        persist()
    }

    func unarchive(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id && $0.profileID == selectedProfileID && $0.isArchived }) else { return }
        conversations[index].isArchived = false
        persist()
    }

    func newConversation() {
        let conversation = Conversation(profileID: selectedProfileID, title: "New conversation")
        conversations.insert(conversation, at: 0)
        activeID = conversation.id
        defaults.set(conversation.id.uuidString, forKey: "conversation.activeID.\(selectedProfileID)")
        persist()
    }

    @discardableResult
    func append(_ message: ChatMessage) -> Bool {
        guard !needsRecovery, let index = conversations.firstIndex(where: { $0.id == activeID }) else { return false }
        let previous = conversations
        conversations[index].append(message)
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persist()
        if persistenceError != nil {
            conversations = previous
            return false
        }
        return true
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
        guard conversations.contains(where: { $0.id == id && $0.profileID == selectedProfileID }) else { return }
        conversations.removeAll { $0.id == id }
        if visibleConversations.isEmpty { conversations.insert(Conversation(profileID: selectedProfileID, title: "New conversation"), at: 0) }
        if !visibleConversations.contains(where: { $0.id == activeID }) {
            activeID = visibleConversations[0].id
            defaults.set(activeID.uuidString, forKey: "conversation.activeID.\(selectedProfileID)")
        }
        persist()
    }

    private func persist() {
        guard !needsRecovery else { return }
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

    private static func load(from url: URL) throws -> [Conversation] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Conversation].self, from: data)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func latestArchive(beside url: URL) -> URL? { archives(beside: url).first }

    private static func recoveryMarker(beside url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".recovery-pending")
    }

    private static func archives(beside url: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        )) ?? []
        return files.filter { candidate in
            candidate.lastPathComponent.hasPrefix(url.lastPathComponent + ".unreadable-") &&
            ((try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false)
        }.sorted { left, right in
            let a = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a == b ? left.lastPathComponent < right.lastPathComponent : a > b
        }
    }

    private static func defaultFileURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Yanuseu", isDirectory: true).appendingPathComponent("conversations.json")
    }
}
