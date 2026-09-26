import Combine
import Foundation

struct LocalSkill: Codable, Equatable, Identifiable {
    let id: String
    let summary: String
    let instructions: String
}

enum SkillError: LocalizedError {
    case invalidDocument, tooLarge, unsupportedPlatform, unreadableLibrary, unknownSkill
    var errorDescription: String? {
        switch self {
        case .invalidDocument: "Choose a UTF-8 SKILL.md with name, description, and nonempty instructions."
        case .tooLarge: "The skill file exceeds 16 KB."
        case .unsupportedPlatform: "This skill does not declare iOS compatibility."
        case .unreadableLibrary: "The local skill library could not be read; nothing was overwritten."
        case .unknownSkill: "That skill is not in the local library."
        }
    }
}

@MainActor
final class SkillStore: ObservableObject {
    private struct Document: Codable {
        var version: Int
        var skills: [LocalSkill]
        var enabled: [String: Set<String>]
    }

    @Published private(set) var skills: [LocalSkill] = []
    @Published private(set) var enabled: [String: Set<String>] = [:]
    @Published private(set) var storageError: String?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Yanuseu", isDirectory: true).appendingPathComponent("skills.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: self.fileURL))
            guard document.version == 1 else { throw SkillError.unreadableLibrary }
            skills = document.skills
            enabled = document.enabled
        } catch {
            storageError = SkillError.unreadableLibrary.localizedDescription
        }
    }

    func isEnabled(_ skillID: String, profileID: String) -> Bool {
        enabled[profileID]?.contains(skillID) == true
    }

    func instructions(for profileID: String) -> [String] {
        guard storageError == nil else { return [] }
        var remaining = 4_000
        return skills.filter { isEnabled($0.id, profileID: profileID) }.sorted { $0.id < $1.id }.compactMap { skill in
            let entry = "Skill \(skill.id) (user-reviewed instructions; not a tool permission):\n\(skill.instructions)"
            guard entry.count <= remaining else { return nil }
            remaining -= entry.count
            return entry
        }
    }

    @discardableResult
    func importSkill(data: Data) throws -> LocalSkill {
        guard storageError == nil else { throw SkillError.unreadableLibrary }
        let skill = try Self.parse(data)
        var next = skills.filter { $0.id != skill.id }
        guard next.count < 20 else { throw SkillError.tooLarge }
        next.append(skill)
        next.sort { $0.id < $1.id }
        var newEnabled = enabled
        // Replacing a skill must never silently keep its prior approval.
        for profile in newEnabled.keys { newEnabled[profile]?.remove(skill.id) }
        try persist(skills: next, enabled: newEnabled)
        skills = next
        enabled = newEnabled
        return skill
    }

    func setEnabled(_ value: Bool, skillID: String, profileID: String) throws {
        guard storageError == nil else { throw SkillError.unreadableLibrary }
        guard skills.contains(where: { $0.id == skillID }) else { throw SkillError.unknownSkill }
        var next = enabled
        if value { next[profileID, default: []].insert(skillID) }
        else { next[profileID]?.remove(skillID) }
        try persist(skills: skills, enabled: next)
        enabled = next
    }

    static func parse(_ data: Data) throws -> LocalSkill {
        guard data.count <= 16_384 else { throw SkillError.tooLarge }
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw SkillError.invalidDocument }
        let lines = text.components(separatedBy: .newlines)
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---"), end + 1 < lines.count else { throw SkillError.invalidDocument }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 { fields[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        func unquote(_ input: String) -> String {
            if input.count >= 2, let first = input.first, first == input.last, first == "\"" || first == "'" { return String(input.dropFirst().dropLast()) }
            return input
        }
        guard let rawName = fields["name"], let rawSummary = fields["description"] else { throw SkillError.invalidDocument }
        let name = unquote(rawName)
        let summary = unquote(rawSummary)
        let validSlug = !name.isEmpty && name.count <= 48 && name.unicodeScalars.allSatisfy {
            (97...122).contains($0.value) || (48...57).contains($0.value) || $0.value == 45 || $0.value == 95
        }
        guard validSlug, !summary.isEmpty, summary.count <= 180 else { throw SkillError.invalidDocument }
        if let platforms = fields["platforms"] {
            let tokens = unquote(platforms).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                .split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)).lowercased() }
            guard tokens.contains("ios") else { throw SkillError.unsupportedPlatform }
        }
        let body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 8_000 else { throw SkillError.invalidDocument }
        return LocalSkill(id: name, summary: summary, instructions: body)
    }

    private func persist(skills: [LocalSkill], enabled: [String: Set<String>]) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        var directory = parent
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let data = try JSONEncoder().encode(Document(version: 1, skills: skills, enabled: enabled))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
