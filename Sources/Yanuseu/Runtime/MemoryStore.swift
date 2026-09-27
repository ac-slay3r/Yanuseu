import Combine
import Foundation

struct LocalMemoryNote: Codable, Equatable, Identifiable {
    enum Provenance: String, Codable { case userEntered }
    let id: UUID
    let profileID: String
    var text: String
    let provenance: Provenance
    let createdAt: Date
    var updatedAt: Date
}

enum MemoryStoreError: LocalizedError {
    case unreadable, invalidNote, notFound, full, contextTooLarge
    var errorDescription: String? {
        switch self {
        case .unreadable: "Local memory could not be read. Nothing was overwritten; restore the file and retry."
        case .invalidNote: "Enter a note of 1–2,000 characters."
        case .notFound: "That note does not belong to this profile."
        case .full: "This profile has reached the 20-note limit."
        case .contextTooLarge: "Memory exceeds the 3,000-character turn limit. Shorten or delete a note first."
        }
    }
}

@MainActor
final class MemoryStore: ObservableObject {
    private struct Document: Codable { var version: Int; var notes: [LocalMemoryNote] }
    @Published private(set) var notes: [LocalMemoryNote] = []
    @Published private(set) var storageError: String?
    private let fileURL: URL
    private var savedData: Data?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Yanuseu", isDirectory: true).appendingPathComponent("memory.json")
        if FileManager.default.fileExists(atPath: self.fileURL.path) { try? reload() }
    }

    func reload() throws {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(Document.self, from: data)
            guard decoded.version == 1, decoded.notes.count <= 200,
                  Set(decoded.notes.map(\.id)).count == decoded.notes.count,
                  decoded.notes.allSatisfy({ !$0.profileID.isEmpty && Self.valid($0.text) }),
                  Set(decoded.notes.map(\.profileID)).allSatisfy({ id in decoded.notes.filter { $0.profileID == id }.count <= 20 })
            else { throw MemoryStoreError.unreadable }
            for id in Set(decoded.notes.map(\.profileID)) {
                _ = try Self.render(decoded.notes.filter { $0.profileID == id })
            }
            notes = decoded.notes
            savedData = data
            storageError = nil
        } catch {
            storageError = MemoryStoreError.unreadable.localizedDescription
            throw MemoryStoreError.unreadable
        }
    }

    func notes(for profileID: String) -> [LocalMemoryNote] {
        notes.filter { $0.profileID == profileID }.sorted { $0.createdAt < $1.createdAt }
    }

    func context(for profileID: String) throws -> [String] {
        guard storageError == nil else { throw MemoryStoreError.unreadable }
        try verifyUnchanged()
        return try Self.render(notes(for: profileID))
    }

    @discardableResult
    func add(_ text: String, profileID: String) throws -> LocalMemoryNote {
        guard storageError == nil else { throw MemoryStoreError.unreadable }
        guard !profileID.isEmpty else { throw MemoryStoreError.invalidNote }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.valid(cleaned) else { throw MemoryStoreError.invalidNote }
        guard notes(for: profileID).count < 20 else { throw MemoryStoreError.full }
        let now = Date()
        let note = LocalMemoryNote(id: UUID(), profileID: profileID, text: cleaned,
                                   provenance: .userEntered, createdAt: now, updatedAt: now)
        let next = notes + [note]
        _ = try Self.render(next.filter { $0.profileID == profileID })
        try persist(next)
        notes = next
        return note
    }

    func edit(_ id: UUID, text: String, profileID: String) throws {
        guard storageError == nil else { throw MemoryStoreError.unreadable }
        guard let index = notes.firstIndex(where: { $0.id == id && $0.profileID == profileID }) else { throw MemoryStoreError.notFound }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.valid(cleaned) else { throw MemoryStoreError.invalidNote }
        var next = notes
        next[index].text = cleaned
        next[index].updatedAt = Date()
        _ = try Self.render(next.filter { $0.profileID == profileID })
        try persist(next)
        notes = next
    }

    func delete(_ id: UUID, profileID: String) throws {
        guard storageError == nil else { throw MemoryStoreError.unreadable }
        guard notes.contains(where: { $0.id == id && $0.profileID == profileID }) else { throw MemoryStoreError.notFound }
        let next = notes.filter { $0.id != id }
        try persist(next)
        notes = next
    }

    private static func valid(_ text: String) -> Bool {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        return count > 0 && count <= 2_000 && !text.contains("\0")
    }

    private static func render(_ notes: [LocalMemoryNote]) throws -> [String] {
        let entries = notes.sorted { $0.createdAt < $1.createdAt }.map { "- \($0.text)" }
        guard entries.joined(separator: "\n").count <= 3_000 else { throw MemoryStoreError.contextTooLarge }
        return entries
    }

    private func persist(_ next: [LocalMemoryNote]) throws {
        try verifyUnchanged()
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        var protectedDirectory = parent
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedDirectory.setResourceValues(values)
        let data = try JSONEncoder().encode(Document(version: 1, notes: next))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        savedData = data
    }

    private func verifyUnchanged() throws {
        do {
            let current = FileManager.default.fileExists(atPath: fileURL.path) ? try Data(contentsOf: fileURL) : nil
            guard current == savedData else { throw MemoryStoreError.unreadable }
        } catch {
            storageError = MemoryStoreError.unreadable.localizedDescription
            throw MemoryStoreError.unreadable
        }
    }
}
