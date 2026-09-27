import XCTest
@testable import Yanuseu

@MainActor
final class ToolPolicyTests: XCTestCase {
    func testOnlyAuthorizedKnownCapabilitiesAreOfferedAndExecuted() {
        let call = ToolCall(id: "1", function: .init(name: "calculator", arguments: "{\"expression\":\"7*6\"}"))
        let off = ToolPolicy()
        XCTAssertTrue(ToolRegistry.schemas(for: off).isEmpty)
        XCTAssertTrue(ToolExecutor.execute(call, policy: off).contains("disabled"))
        let on = ToolPolicy(allowed: [.calculator])
        let schema = ToolRegistry.schemas(for: on).first?["function"] as? [String: Any]
        XCTAssertEqual(schema?["name"] as? String, "calculator")
        XCTAssertEqual(ToolExecutor.execute(call, policy: on), "42")
        let unknown = ToolCall(id: "2", function: .init(name: "shell", arguments: "{}"))
        XCTAssertEqual(ToolExecutor.execute(unknown, policy: on), "That tool is unavailable; no action was taken.")
    }

    func testProfileSettingPersistsWhileDefaultRemainsOffAndPayloadMatchesGate() throws {
        let suite = "YanuseuToolPolicy-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profiles = ProfileStore(defaults: defaults)
        XCTAssertFalse(profiles.selected.calculatorEnabled)
        let disabled = ToolPolicy(calculatorEnabled: profiles.selected.calculatorEnabled)
        XCTAssertNil(ChatService.requestPayload(messages: [], model: "test", policy: disabled)["tools"])
        let first = profiles.selected.id
        profiles.updateSettings(profileID: first, instructions: "Keep", calculatorEnabled: true)
        let enabled = ToolPolicy(calculatorEnabled: ProfileStore(defaults: defaults).selected.calculatorEnabled)
        XCTAssertEqual(ToolRegistry.schemas(for: enabled).count, 1)
        XCTAssertEqual((ChatService.requestPayload(messages: [], model: "test", policy: enabled)["tools"] as? [[String: Any]])?.count, 1)
        let second = profiles.create(name: "Other")
        XCTAssertFalse(second.calculatorEnabled)
        XCTAssertTrue(ToolRegistry.schemas(for: ToolPolicy(calculatorEnabled: second.calculatorEnabled)).isEmpty)
    }
}
