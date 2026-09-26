import XCTest
@testable import Yanuseu

final class AgentCommandTests: XCTestCase {
    func testParsesSupportedLocalCommandsCaseInsensitively() {
        XCTAssertEqual(AppCommand.parse("/HELP"), .help)
        XCTAssertEqual(AppCommand.parse("/new"), .newConversation)
        XCTAssertEqual(AppCommand.parse("/clear"), .clearConversation)
        XCTAssertEqual(AppCommand.parse("/tools"), .tools)
        XCTAssertEqual(AppCommand.parse("/settings"), .settings)
    }

    func testCommandRegistryPowersHelpAndSlashSuggestions() {
        let entries = AppCommand.registry
        XCTAssertEqual(Set(entries.map(\.name)).count, entries.count)
        for entry in entries {
            XCTAssertEqual(AppCommand.parse(entry.name), entry.command)
            XCTAssertTrue(AppCommand.helpText.contains(entry.name))
            XCTAssertFalse(entry.summary.isEmpty)
        }
        XCTAssertEqual(AppCommand.suggestions(for: "/NE" ).map(\.name), ["/new"])
        XCTAssertEqual(AppCommand.suggestions(for: "/" ).count, entries.count)
        XCTAssertTrue(AppCommand.suggestions(for: "Hello").isEmpty)
        XCTAssertTrue(AppCommand.suggestions(for: "/new extra").isEmpty)
    }

    func testOrdinaryTextIsNotACommandAndUnknownCommandsStayLocal() {
        XCTAssertNil(AppCommand.parse("help me with this"))
        XCTAssertEqual(AppCommand.parse("/unknown"), .unknown("/unknown"))
        XCTAssertEqual(AppCommand.parse("/new extra"), .unknown("/new"))
    }
}
