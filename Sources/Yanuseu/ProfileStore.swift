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
    static let defaultID = "default"
    static let storageKey = "profiles.v1"
    private struct Document: Codable {
        var version: Int
        var profiles: [AgentProfile]
        var selectedID: String
    }

    @Published private(set) var profiles: [AgentProfile]
    @Published private(set) var selectedID: String
    private let defaults: UserDefaults

    var selected: AgentProfile { profiles.first { $0.id == selectedID } ?? profiles[0] }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
            persist()
        }
    }

    @discardableResult
    func create(name: String) -> AgentProfile {
        let profile = AgentProfile(id: UUID().uuidString, name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
                                   baseURL: "https://api.openai.com/v1", model: "", instructions: "",
                                   calculatorEnabled: false, isConfigured: false)
        profiles.append(profile)
        selectedID = profile.id
        persist()
        return profile
    }

    func select(_ id: String) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedID = id
        persist()
    }

    func updateSelected(baseURL: String, model: String, instructions: String, calculatorEnabled: Bool, configured: Bool? = nil) {
        guard let index = profiles.firstIndex(where: { $0.id == selectedID }) else { return }
        profiles[index].baseURL = baseURL
        profiles[index].model = model
        profiles[index].instructions = String(instructions.prefix(4_000))
        profiles[index].calculatorEnabled = calculatorEnabled
        if let configured { profiles[index].isConfigured = configured }
        persist()
    }

    func removeKeyStatus() {
        guard let index = profiles.firstIndex(where: { $0.id == selectedID }) else { return }
        profiles[index].isConfigured = false
        persist()
    }

    private func persist() {
        let document = Document(version: 1, profiles: profiles, selectedID: selectedID)
        if let data = try? JSONEncoder().encode(document) { defaults.set(data, forKey: Self.storageKey) }
    }
}
