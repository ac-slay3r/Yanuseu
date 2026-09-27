import Foundation
import XCTest
@testable import Yanuseu

@MainActor
final class MemoryStoreTests: XCTestCase {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("memory.json")
    }

    func testCorrectionAndDeletionPersistOnlyForOwningProfileAndFuturePayload() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MemoryStore(fileURL: url)
        let note = try store.add("I prefer concise replies", profileID: "personal")
        XCTAssertEqual(note.provenance, .userEntered)
        XCTAssertTrue(store.notes(for: "work").isEmpty)
        let previous = try store.context(for: "personal")
        let first = ChatService.requestPayload(messages: [], model: "test", calculatorEnabled: false, memory: previous)
        try store.edit(note.id, text: "I prefer detailed replies", profileID: "personal")
        let reloaded = MemoryStore(fileURL: url)
        XCTAssertEqual(reloaded.notes(for: "personal").first?.text, "I prefer detailed replies")
        XCTAssertTrue(reloaded.notes(for: "work").isEmpty)
        let corrected = try reloaded.context(for: "personal")
        let second = ChatService.requestPayload(messages: [], model: "test", calculatorEnabled: false, memory: corrected)
        XCTAssertTrue(String(describing: first).contains("concise replies"))
        XCTAssertFalse(String(describing: first).contains("detailed replies"))
        XCTAssertTrue(String(describing: second).contains("detailed replies"))
        XCTAssertFalse(String(describing: second).contains("concise replies"))
        try reloaded.delete(note.id, profileID: "personal")
        XCTAssertTrue(try MemoryStore(fileURL: url).context(for: "personal").isEmpty)
    }

    func testRejectsCrossProfileMutationAndInvalidOrOversizedContent() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MemoryStore(fileURL: url)
        let note = try store.add("Valid note", profileID: "personal")
        XCTAssertThrowsError(try store.edit(note.id, text: "Wrong owner", profileID: "work"))
        XCTAssertThrowsError(try store.delete(note.id, profileID: "work"))
        XCTAssertThrowsError(try store.add("  ", profileID: "personal"))
        XCTAssertThrowsError(try store.add(String(repeating: "a", count: 2_001), profileID: "personal"))
        XCTAssertEqual(store.notes(for: "personal").map(\.text), ["Valid note"])
    }

    func testUnreadableMemoryFailsClosedWithoutOverwritingAndCanReload() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MemoryStore(fileURL: url)
        try store.add("Keep me", profileID: "personal")
        let saved = try Data(contentsOf: url)
        try Data("broken".utf8).write(to: url)
        let blocked = MemoryStore(fileURL: url)
        XCTAssertNotNil(blocked.storageError)
        XCTAssertThrowsError(try blocked.context(for: "personal"))
        XCTAssertThrowsError(try blocked.add("Do not overwrite", profileID: "personal"))
        XCTAssertEqual(try Data(contentsOf: url), Data("broken".utf8))
        try saved.write(to: url)
        try blocked.reload()
        XCTAssertEqual(try blocked.context(for: "personal").count, 1)
    }

    func testContextBudgetRejectsMutationInsteadOfSilentlyDroppingNotes() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MemoryStore(fileURL: url)
        try store.add(String(repeating: "a", count: 1_900), profileID: "personal")
        XCTAssertThrowsError(try store.add(String(repeating: "b", count: 1_900), profileID: "personal"))
        XCTAssertEqual(store.notes(for: "personal").count, 1)
    }

    func testExternalDriftBlocksFutureRequestAndMutationUntilReload() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = MemoryStore(fileURL: url)
        let second = MemoryStore(fileURL: url)
        try first.add("First", profileID: "personal")
        XCTAssertThrowsError(try second.add("Stale write", profileID: "personal"))
        XCTAssertEqual(try first.context(for: "personal").count, 1)
        try Data("corrupted".utf8).write(to: url)
        XCTAssertThrowsError(try first.context(for: "personal"))
        XCTAssertThrowsError(try first.edit(try XCTUnwrap(first.notes.first).id, text: "Overwrite", profileID: "personal"))
        XCTAssertEqual(try Data(contentsOf: url), Data("corrupted".utf8))
    }

    func testDocumentWideLimitCannotMakeAllProfilesUnreadableAfterRestart() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = MemoryStore(fileURL: url)
        for profile in 0..<10 {
            for index in 0..<20 {
                try store.add("Note \(index)", profileID: "profile-\(profile)")
            }
        }
        XCTAssertThrowsError(try store.add("Overflow", profileID: "profile-10"))
        let reloaded = MemoryStore(fileURL: url)
        XCTAssertNil(reloaded.storageError)
        XCTAssertEqual(reloaded.notes(for: "profile-0").count, 20)
    }
}
