import Combine
import Foundation

struct AgentProfile: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var baseURL: String
    var model: String
    var instructions: String
    var calculatorEnabled: Bool
    var isConfigured: Bool
}

@MainActor
final class ProfileStore: ObservableObject {
    nonisolated static let defaultID = "default"
    static let storageKey = "profiles.v1"
    private struct Document: Codable {
        var version: Int
        var profiles: [AgentProfile]
        var selectedID: String
    }

    @Published private(set) var profiles: [AgentProfile]
    @Published private(set) var selectedID: String
    @Published private(set) var storageError: String?
    @Published private(set) var recoveredProfilesURL: URL?
    private let defaults: UserDefaults
    private let archiveDirectory: URL
    private var drafts: [String: String] = [:]

    func draft(for profileID: String) -> String { drafts[profileID] ?? "" }
    func saveDraft(_ text: String, for profileID: String) { drafts[profileID] = text }

    var selected: AgentProfile { profiles.first { $0.id == selectedID } ?? profiles[0] }

    var archivedProfilesURLs: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: archiveDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("profiles.v1.unreadable-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    init(defaults: UserDefaults = .standard, archiveDirectory: URL? = nil) {
        self.defaults = defaults
        self.archiveDirectory = archiveDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Yanuseu", isDirectory: true)
        if let data = defaults.data(forKey: Self.storageKey),
           let document = try? JSONDecoder().decode(Document.self, from: data),
           document.version == 1, !document.profiles.isEmpty,
           document.profiles.contains(where: { $0.id == document.selectedID }) {
            profiles = document.profiles
            selectedID = document.selectedID
        } else {
            profiles = [AgentProfile(id: Self.defaultID, name: "Default",
                                     baseURL: defaults.string(forKey: "provider.baseURL") ?? "https://api.openai.com/v1",
                                     model: defaults.string(forKey: "provider.model") ?? "",
                                     instructions: defaults.string(forKey: "agent.instructions") ?? "",
                                     calculatorEnabled: defaults.bool(forKey: "agent.calculator.enabled"),
                                     isConfigured: defaults.bool(forKey: "provider.isConfigured"))]
            selectedID = Self.defaultID
            if defaults.object(forKey: Self.storageKey) != nil {
                storageError = "Saved profiles could not be read. No profiles or credentials were overwritten."
            } else {
                persist()
            }
        }
    }

    func archiveUnreadableProfilesAndReset() throws -> URL {
        guard storageError != nil, let original = defaults.data(forKey: Self.storageKey) else {
            throw ProfileRecoveryError.noArchiveData
        }
        try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        var directory = archiveDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let archive = archiveDirectory.appendingPathComponent("profiles.v1.unreadable-\(UUID().uuidString).json")
        try original.write(to: archive, options: [.atomic, .completeFileProtection])
        guard try Data(contentsOf: archive) == original else { throw ProfileRecoveryError.couldNotArchive }
        defaults.removeObject(forKey: Self.storageKey)
        storageError = nil
        recoveredProfilesURL = archive
        persist()
        return archive
    }

    enum ProfileRecoveryError: LocalizedError {
        case noArchiveData, couldNotArchive
        var errorDescription: String? {
            switch self {
            case .noArchiveData: "Could not read the original profile bytes. Nothing was reset."
            case .couldNotArchive: "Could not verify the profile archive. Nothing was reset."
            }
        }
    }

    @discardableResult
    func create(name: String) -> AgentProfile {
        guard storageError == nil else { return selected }
        let profile = AgentProfile(id: UUID().uuidString, name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
                                   baseURL: "https://api.openai.com/v1", model: "", instructions: "",
                                   calculatorEnabled: false, isConfigured: false)
        profiles.append(profile)
        selectedID = profile.id
        persist()
        return profile
    }

    func select(_ id: String) {
        guard storageError == nil else { return }
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedID = id
        persist()
    }

    func updateSelected(baseURL: String, model: String, instructions: String, calculatorEnabled: Bool, configured: Bool? = nil) {
        guard storageError == nil else { return }
        guard let index = profiles.firstIndex(where: { $0.id == selectedID }) else { return }
        profiles[index].baseURL = baseURL
        profiles[index].model = model
        profiles[index].instructions = String(instructions.prefix(4_000))
        profiles[index].calculatorEnabled = calculatorEnabled
        if let configured { profiles[index].isConfigured = configured }
        persist()
    }

    func updateSettings(profileID: String, instructions: String, calculatorEnabled: Bool) {
        guard storageError == nil else { return }
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].instructions = String(instructions.prefix(4_000))
        profiles[index].calculatorEnabled = calculatorEnabled
        persist()
    }

    func configure(profileID: String, baseURL: String, model: String, instructions: String, calculatorEnabled: Bool) {
        guard storageError == nil else { return }
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].baseURL = baseURL
        profiles[index].model = model
        profiles[index].instructions = String(instructions.prefix(4_000))
        profiles[index].calculatorEnabled = calculatorEnabled
        profiles[index].isConfigured = true
        persist()
    }

    func resetProvider(profileID: String) {
        guard storageError == nil else { return }
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].isConfigured = false
        persist()
    }

    private func persist() {
        guard storageError == nil else { return }
        let document = Document(version: 1, profiles: profiles, selectedID: selectedID)
        if let data = try? JSONEncoder().encode(document) { defaults.set(data, forKey: Self.storageKey) }
    }
}
