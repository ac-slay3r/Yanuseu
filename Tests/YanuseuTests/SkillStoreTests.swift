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
        XCTAssertTrue(store.instructions(for: "personal").isEmpty)
        store.setEnabled(true, skillID: skill.id, profileID: "personal")
        XCTAssertTrue(store.instructions(for: "personal").joined().contains("Explain a calculation"))
        XCTAssertTrue(store.instructions(for: "work").isEmpty)
        XCTAssertEqual(SkillStore(fileURL: file).instructions(for: "personal"), store.instructions(for: "personal"))
        _ = try store.importSkill(data: Data(sample.replacingOccurrences(of: "clearly", with: "carefully").utf8))
        XCTAssertTrue(store.instructions(for: "personal").isEmpty, "Reimport requires explicit review and re-enable")
    }

    func testRejectsUnsupportedAndOversizedSkillWithoutEnablingIt() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("skills.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SkillStore(fileURL: file)
        XCTAssertThrowsError(try store.importSkill(data: Data(sample.replacingOccurrences(of: "[ios]", with: "[linux]").utf8)))
        XCTAssertThrowsError(try store.importSkill(data: Data(repeating: 65, count: 16_385)))
        XCTAssertTrue(store.skills.isEmpty)
    }

    func testSkillInstructionsDoNotGrantCalculatorAndDisabledSkillIsNotSent() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("skills.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SkillStore(fileURL: file)
        _ = try store.importSkill(data: Data(sample.utf8))
        let without = ChatService.requestPayload(messages: [], model: "test", calculatorEnabled: false, skills: store.instructions(for: "personal"))
        XCTAssertNil(without["tools"])
        XCTAssertFalse(String(describing: without).contains("Explain a calculation"))
        store.setEnabled(true, skillID: "explain-math", profileID: "personal")
        let with = ChatService.requestPayload(messages: [], model: "test", calculatorEnabled: false, skills: store.instructions(for: "personal"))
        XCTAssertNil(with["tools"])
        XCTAssertTrue(String(describing: with).contains("Explain a calculation"))
        let denied = ToolExecutor.execute(ToolCall(id: "1", function: .init(name: "calculator", arguments: "{\"expression\":\"2+2\"}")), calculatorEnabled: false)
        XCTAssertTrue(denied.contains("disabled"))
    }
}
