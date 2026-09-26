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

    func testOrdinaryTextIsNotACommandAndUnknownCommandsStayLocal() {
        XCTAssertNil(AppCommand.parse("help me with this"))
        XCTAssertEqual(AppCommand.parse("/unknown"), .unknown("/unknown"))
        XCTAssertEqual(AppCommand.parse("/new extra"), .unknown("/new"))
    }
}
