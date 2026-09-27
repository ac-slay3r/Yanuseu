import XCTest
@testable import Yanuseu

@MainActor
final class ConversationStoreTests: XCTestCase {
    func testOrphanedSessionsRequireExplicitRecoveryIntoSelectedProfile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = ConversationStore(fileURL: file)
        store.switchProfile("lost-profile")
        store.append(ChatMessage(role: .user, content: "Old profile only"))
        let lost = store.activeID
        store.switchProfile(ProfileStore.defaultID)
        XCTAssertTrue(store.search("Old profile").isEmpty)
        XCTAssertEqual(store.orphanedConversations(knownProfileIDs: [ProfileStore.defaultID]).map(\.id), [lost])
        XCTAssertFalse(store.recoverOrphanedConversation(lost, knownProfileIDs: [ProfileStore.defaultID, "lost-profile"]))
        XCTAssertTrue(store.recoverOrphanedConversation(lost, knownProfileIDs: [ProfileStore.defaultID]))
        XCTAssertEqual(store.search("Old profile").map(\.id), [lost])
        XCTAssertEqual(ConversationStore(fileURL: file).search("Old profile").map(\.id), [lost])
    }

    func testFailedMessagePersistenceDoesNotConsumeOrDuplicateTheMessage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(fileURL: directory.appendingPathComponent("history.json"))
        let message = ChatMessage(role: .user, content: "Do not lose this draft")
        XCTAssertFalse(store.append(message))
        XCTAssertTrue(store.activeConversation.messages.isEmpty)
        XCTAssertNotNil(store.persistenceError)
    }

    func testProfileSwitchSearchResumeArchiveAndDeleteScenarioAcrossReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("history.json")
        let suite = "YanuseuTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = ConversationStore(fileURL: file, defaults: defaults)
        store.append(ChatMessage(role: .user, content: "Personal mountain"))
        let personal = store.activeID
        store.switchProfile("work")
        store.append(ChatMessage(role: .user, content: "Work mountain"))
        let work = store.activeID
        XCTAssertEqual(store.search("mountain").map(\.id), [work])
        store.switchProfile(ProfileStore.defaultID)
        XCTAssertEqual(store.search("mountain").map(\.id), [personal])
        store.archive(personal)
        XCTAssertTrue(store.search("mountain").isEmpty)
        let resumed = ConversationStore(fileURL: file, defaults: defaults)
        XCTAssertEqual(resumed.archivedConversations.map(\.id), [personal])
        resumed.select(personal)
        XCTAssertEqual(resumed.activeConversation.messages.map(\.content), ["Personal mountain"])
        resumed.delete(personal)
        XCTAssertTrue(resumed.search("mountain").isEmpty)
        resumed.switchProfile("work")
        XCTAssertEqual(resumed.search("mountain").map(\.id), [work])
        XCTAssertEqual(resumed.activeConversation.messages.map(\.content), ["Work mountain"])
    }

    func testLegacyArchiveFlagDefaultsToVisibleAndRoundTrips() throws {
        let original = Conversation(title: "Legacy")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "isArchived")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Conversation.self, from: legacy)
        XCTAssertFalse(decoded.isArchived)
        var archived = decoded
        archived.isArchived = true
        let roundTrip = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(archived))
        XCTAssertTrue(roundTrip.isArchived)
    }

    func testArchiveHidesSessionAndSelectIntentionallyResumesItAfterReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("history.json")
        let suite = "YanuseuTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = ConversationStore(fileURL: file, defaults: defaults)
        store.append(ChatMessage(role: .user, content: "Archived content"))
        let oldID = store.activeID
        store.archive(oldID)
        XCTAssertNotEqual(store.activeID, oldID)
        XCTAssertFalse(store.visibleConversations.contains { $0.id == oldID })
        XCTAssertEqual(store.archivedConversations.map(\.id), [oldID])
        XCTAssertTrue(store.search("Archived content").isEmpty)
        let restarted = ConversationStore(fileURL: file, defaults: defaults)
        XCTAssertNotEqual(restarted.activeID, oldID)
        XCTAssertEqual(restarted.archivedConversations.map(\.id), [oldID])
        restarted.select(oldID)
        XCTAssertEqual(restarted.activeID, oldID)
        XCTAssertEqual(restarted.activeConversation.messages.map(\.content), ["Archived content"])
        XCTAssertTrue(restarted.archivedConversations.isEmpty)
        XCTAssertEqual(ConversationStore(fileURL: file, defaults: defaults).activeID, oldID)
    }

    func testArchiveUnarchiveAndDeleteStayWithinSelectedProfile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("history.json")
        let suite = "YanuseuTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = ConversationStore(fileURL: file, defaults: defaults)
        let personalID = store.activeID
        store.archive(personalID)
        store.switchProfile("work")
        let workID = store.activeID
        store.archive(personalID)
        store.unarchive(personalID)
        store.select(personalID)
        store.delete(personalID)
        XCTAssertEqual(store.activeID, workID)
        XCTAssertTrue(store.archivedConversations.isEmpty)
        store.archive(workID)
        XCTAssertEqual(store.archivedConversations.map(\.id), [workID])
        store.unarchive(workID)
        XCTAssertTrue(store.archivedConversations.isEmpty)
        XCTAssertTrue(store.visibleConversations.contains { $0.id == workID })
        let restarted = ConversationStore(fileURL: file, defaults: defaults)
        XCTAssertTrue(restarted.archivedConversations.contains { $0.id == personalID })
        XCTAssertFalse(restarted.visibleConversations.contains { $0.id == workID })
        restarted.switchProfile("work")
        XCTAssertTrue(restarted.visibleConversations.contains { $0.id == workID })
        XCTAssertTrue(restarted.archivedConversations.isEmpty)
    }

    func testRecoveryAfterRestartBetweenMoveAndProtectionDoesNotOverwriteOrDuplicateArchive() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("history.json")
        let original = Data("{interrupted".utf8)
        try original.write(to: file)
        let suite = "YanuseuTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let first = ConversationStore(fileURL: file, defaults: defaults)
        XCTAssertThrowsError(try first.archiveUnreadableHistoryAndReset(protectArchive: { _ in
            throw CocoaError(.fileWriteNoPermission)
        }))
        let archive = try XCTUnwrap(first.recoveredHistoryURL)
        let restarted = ConversationStore(fileURL: file, defaults: defaults)
        XCTAssertTrue(restarted.needsRecovery)
        XCTAssertEqual(restarted.recoveredHistoryURL, archive)
        restarted.append(ChatMessage(role: .user, content: "Do not persist"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        var retriedURL: URL?
        try restarted.archiveUnreadableHistoryAndReset(protectArchive: { retriedURL = $0 })
        XCTAssertEqual(retriedURL, archive)
        XCTAssertEqual(restarted.archivedHistoryURLs.count, 1)
        XCTAssertEqual(try Data(contentsOf: archive), original)
        XCTAssertFalse(ConversationStore(fileURL: file, defaults: defaults).needsRecovery)
    }

    func testSearchFindsTitleAndMessageOnlyWithinSelectedProfileAndResumesAfterReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("history.json")
        let suite = "YanuseuTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = ConversationStore(fileURL: file, defaults: defaults)
        store.append(ChatMessage(role: .user, content: "Saturn rings"))
        let saturnID = store.activeID
        store.newConversation()
        store.rename(store.activeID, to: "Jupiter notes")
        XCTAssertEqual(store.search(" satURN ").map(\.id), [saturnID])
        XCTAssertEqual(store.search("JUPITER").count, 1)
        store.switchProfile("work")
        store.append(ChatMessage(role: .user, content: "Saturn work"))
        XCTAssertEqual(store.search("saturn").count, 1)
        XCTAssertNotEqual(store.search("saturn").first?.id, saturnID)
        store.switchProfile(ProfileStore.defaultID)
        store.select(saturnID)
        let restored = ConversationStore(fileURL: file, defaults: defaults)
        XCTAssertEqual(restored.activeID, saturnID)
        XCTAssertEqual(restored.activeConversation.messages.map(\.content), ["Saturn rings"])
    }

    func testUnreadableHistoryCannotBeOverwrittenUntilExplicitRecoveryAndOriginalIsArchived() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("history.json")
        let original = Data("{broken history".utf8)
        try original.write(to: file)
        let suite = "YanuseuTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = ConversationStore(fileURL: file, defaults: defaults)
        XCTAssertTrue(store.needsRecovery)
        XCTAssertNotNil(store.persistenceError)
        store.append(ChatMessage(role: .user, content: "Should not overwrite"))
        XCTAssertEqual(try Data(contentsOf: file), original)
        try store.archiveUnreadableHistoryAndReset()
        XCTAssertFalse(store.needsRecovery)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(store.recoveredHistoryURL)), original)
        XCTAssertEqual(ConversationStore(fileURL: file, defaults: defaults).recoveredHistoryURL, store.recoveredHistoryURL)
        XCTAssertTrue(try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: file)).allSatisfy { $0.messages.isEmpty })
    }

    func testArchiveRemainsExportableIfResetFailsAfterMoveAndCanBeRetried() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("history.json")
        let original = Data("{damaged".utf8)
        try original.write(to: file)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(fileURL: file)
        XCTAssertThrowsError(try store.archiveUnreadableHistoryAndReset(protectArchive: { _ in
            throw CocoaError(.fileWriteNoPermission)
        }))
        XCTAssertTrue(store.needsRecovery)
        XCTAssertEqual(store.archivedHistoryURLs.count, 1)
        XCTAssertEqual(try Data(contentsOf: store.archivedHistoryURLs[0]), original)
        try store.archiveUnreadableHistoryAndReset()
        XCTAssertFalse(store.needsRecovery)
        XCTAssertEqual(try Data(contentsOf: store.archivedHistoryURLs[0]), original)
        try Data("{again".utf8).write(to: file)
        let second = ConversationStore(fileURL: file)
        try second.archiveUnreadableHistoryAndReset()
        XCTAssertEqual(second.archivedHistoryURLs.count, 2)
        XCTAssertTrue(second.archivedHistoryURLs.contains { (try? Data(contentsOf: $0)) == original })
    }

    func testLegacyJSONRemainsReadableAndSearchableAfterOpening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("history.json")
        let old = Conversation(title: "Original", messages: [ChatMessage(role: .user, content: "legacy comet")])
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        dictionary.removeValue(forKey: "profileID")
        try JSONSerialization.data(withJSONObject: [dictionary]).write(to: file)
        let store = ConversationStore(fileURL: file)
        XCTAssertFalse(store.needsRecovery)
        XCTAssertEqual(store.search("comet").first?.id, old.id)
        XCTAssertEqual(store.activeConversation.profileID, ProfileStore.defaultID)
    }

    func testProfilesCannotSelectOrClearEachOthersSessions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("history.json")
        let suite = "YanuseuTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = ConversationStore(fileURL: file, defaults: defaults)
        store.append(ChatMessage(role: .user, content: "Default only"))
        let first = store.activeID
        store.switchProfile("another-profile")
        XCTAssertTrue(store.visibleConversations.allSatisfy { $0.profileID == "another-profile" })
        store.select(first)
        XCTAssertNotEqual(store.activeID, first)
        store.append(ChatMessage(role: .user, content: "Other only"))
        store.deleteAll()
        store.switchProfile(ProfileStore.defaultID)
        XCTAssertEqual(store.activeID, first)
        XCTAssertEqual(store.activeConversation.messages.map(\.content), ["Default only"])
        let restored = ConversationStore(fileURL: file, defaults: defaults, profileID: "another-profile")
        XCTAssertTrue(restored.visibleConversations.allSatisfy { $0.profileID == "another-profile" })
        XCTAssertTrue(restored.activeConversation.messages.isEmpty)
    }

    func testLegacyConversationDecodesIntoDefaultProfile() throws {
        let message = ChatMessage(role: .user, content: "Legacy")
        let encoded = try JSONEncoder().encode(Conversation(title: "Old", messages: [message]))
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        dictionary.removeValue(forKey: "profileID")
        let legacy = try JSONSerialization.data(withJSONObject: dictionary)
        XCTAssertEqual(try JSONDecoder().decode(Conversation.self, from: legacy).profileID, ProfileStore.defaultID)
    }

    func testClearingActiveConversationPreservesOtherConversations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("history.json")
        let suite = "YanuseuTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }

        let store = ConversationStore(fileURL: file, defaults: defaults)
        store.append(ChatMessage(role: .user, content: "Keep this older conversation"))
        let olderID = store.activeID
        store.newConversation()
        store.append(ChatMessage(role: .user, content: "Clear only this one"))
        let activeID = store.activeID

        store.clearActiveConversation()

        XCTAssertEqual(store.activeID, activeID)
        XCTAssertTrue(store.activeConversation.messages.isEmpty)
        XCTAssertEqual(store.conversations.first(where: { $0.id == olderID })?.messages.map(\.content), ["Keep this older conversation"])
    }

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
        let directoryValues = try XCTUnwrap(try? file.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]))
        XCTAssertEqual(directoryValues.isExcludedFromBackup, true)
        store.append(ChatMessage(role: .user, content: "Remember this locally"))
        let conversationID = store.activeID
        let restored = ConversationStore(fileURL: file, defaults: defaults)

        XCTAssertEqual(restored.activeID, conversationID)
        XCTAssertEqual(restored.activeConversation.messages.map(\.content), ["Remember this locally"])
        restored.deleteAll()
        let cleared = ConversationStore(fileURL: file, defaults: defaults)
        XCTAssertTrue(cleared.activeConversation.messages.isEmpty)
        XCTAssertEqual(cleared.conversations.count, 1)
    }
}
