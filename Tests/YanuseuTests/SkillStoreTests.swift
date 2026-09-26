import XCTest
@testable import Yanuseu

@MainActor
final class SkillStoreTests: XCTestCase {
    private let sample = """
    ---
    name: explain-math
    description: Explain each arithmetic step
    platforms: [ios]
    ---
    Explain a calculation clearly. Do not claim to execute tools.
    """

    func testImportStartsDisabledAndEnabledInstructionsAreProfileScopedAndPersisted() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("skills.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SkillStore(fileURL: file)
        let skill = try store.importSkill(data: Data(sample.utf8))
        XCTAssertEqual(skill.id, "explain-math")
        XCTAssertTrue(try store.instructions(for: "personal").isEmpty)
        try store.setEnabled(true, skillID: skill.id, profileID: "personal")
        XCTAssertTrue(try store.instructions(for: "personal").joined().contains("Explain a calculation"))
        XCTAssertTrue(try store.instructions(for: "work").isEmpty)
        XCTAssertEqual(try SkillStore(fileURL: file).instructions(for: "personal"), try store.instructions(for: "personal"))
        _ = try store.importSkill(data: Data(sample.replacingOccurrences(of: "clearly", with: "carefully").utf8))
        XCTAssertTrue(try store.instructions(for: "personal").isEmpty, "Reimport requires explicit review and re-enable")
    }

    func testRejectsUnsupportedAndOversizedSkillWithoutEnablingIt() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("skills.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SkillStore(fileURL: file)
        XCTAssertThrowsError(try store.importSkill(data: Data(sample.replacingOccurrences(of: "[ios]", with: "[linux]").utf8)))
        XCTAssertThrowsError(try store.importSkill(data: Data(repeating: 65, count: 16_385)))
        XCTAssertTrue(store.skills.isEmpty)
    }

    func testOversizedGuidanceIsRejectedWithoutSilentlyOmittingAnEnabledSkill() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("skills.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SkillStore(fileURL: file)
        let longBody = String(repeating: "a", count: 3_900)
        let first = try store.importSkill(data: Data(sample.replacingOccurrences(of: "Explain a calculation clearly. Do not claim to execute tools.", with: longBody).utf8))
        let second = try store.importSkill(data: Data(sample.replacingOccurrences(of: "explain-math", with: "another-skill").utf8))
        try store.setEnabled(true, skillID: first.id, profileID: "personal")
        XCTAssertThrowsError(try store.setEnabled(true, skillID: second.id, profileID: "personal"))
        XCTAssertFalse(store.isEnabled(second.id, profileID: "personal"))
        XCTAssertEqual(try store.instructions(for: "personal").count, 1)
        let oversizedBody = String(repeating: "b", count: 4_000)
        XCTAssertThrowsError(try store.importSkill(data: Data(sample.replacingOccurrences(of: "Explain a calculation clearly. Do not claim to execute tools.", with: oversizedBody).utf8)))
    }

    func testDeleteFreesLibrarySpaceAndRetryRecoversTransientReadError() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("skills.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SkillStore(fileURL: file)
        _ = try store.importSkill(data: Data(sample.utf8))
        try store.setEnabled(true, skillID: "explain-math", profileID: "personal")
        let saved = try Data(contentsOf: file)
        try Data("damaged".utf8).write(to: file)
        let locked = SkillStore(fileURL: file)
        XCTAssertNotNil(locked.storageError)
        XCTAssertThrowsError(try locked.reload())
        try saved.write(to: file)
        try locked.reload()
        XCTAssertNil(locked.storageError)
        XCTAssertEqual(try locked.instructions(for: "personal").count, 1)
        try locked.delete(skillID: "explain-math")
        XCTAssertTrue(locked.skills.isEmpty)
        XCTAssertTrue(try locked.instructions(for: "personal").isEmpty)
    }

    func testCoordinatedFileReadIsBoundedWithoutMetadataSize() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("SKILL.md")
        try Data(sample.utf8).write(to: file)
        XCTAssertEqual(try SkillFileReader.read(file), Data(sample.utf8))
        try Data(repeating: 65, count: 16_385).write(to: file)
        XCTAssertThrowsError(try SkillFileReader.read(file))
    }

    func testSkillInstructionsDoNotGrantCalculatorAndDisabledSkillIsNotSent() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("skills.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SkillStore(fileURL: file)
        _ = try store.importSkill(data: Data(sample.utf8))
        let without = ChatService.requestPayload(messages: [], model: "test", calculatorEnabled: false, skills: try store.instructions(for: "personal"))
        XCTAssertNil(without["tools"])
        XCTAssertFalse(String(describing: without).contains("Explain a calculation"))
        try store.setEnabled(true, skillID: "explain-math", profileID: "personal")
        let with = ChatService.requestPayload(messages: [], model: "test", calculatorEnabled: false, skills: try store.instructions(for: "personal"))
        XCTAssertNil(with["tools"])
        XCTAssertTrue(String(describing: with).contains("Explain a calculation"))
        let denied = ToolExecutor.execute(ToolCall(id: "1", function: .init(name: "calculator", arguments: "{\"expression\":\"2+2\"}")), calculatorEnabled: false)
        XCTAssertTrue(denied.contains("disabled"))
    }
}
