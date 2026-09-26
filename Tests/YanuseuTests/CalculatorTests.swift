import XCTest
@testable import Yanuseu

final class CalculatorTests: XCTestCase {
    func testArithmeticHonorsPrecedenceParenthesesAndUnaryMinus() throws {
        XCTAssertEqual(try Calculator.evaluate("2 + 3 * 4"), 14, accuracy: 0.000001)
        XCTAssertEqual(try Calculator.evaluate("(2 + 3) * 4"), 20, accuracy: 0.000001)
        XCTAssertEqual(try Calculator.evaluate("-2.5 * -2"), 5, accuracy: 0.000001)
    }

    func testCalculatorRejectsDivisionByZeroAndNonArithmeticInput() {
        XCTAssertThrowsError(try Calculator.evaluate("8 / (3 - 3)"))
        XCTAssertThrowsError(try Calculator.evaluate("2 + system(1)"))
        XCTAssertThrowsError(try Calculator.evaluate(String(repeating: "1", count: 257)))
    }

    func testProviderStreamParserPreservesPartialCalculatorCalls() throws {
        let startLine = try makeSSE(["choices": [[
            "delta": ["tool_calls": [[
                "index": 0,
                "id": "call_1",
                "type": "function",
                "function": ["name": "calculator", "arguments": "{\"expression\":\"1+"]
            ]]],
            "finish_reason": NSNull()
        ]]])
        let endLine = try makeSSE(["choices": [[
            "delta": ["tool_calls": [[
                "index": 0,
                "function": ["arguments": "2\"}"]
            ]]],
            "finish_reason": NSNull()
        ]]])

        XCTAssertEqual(ChatService.events(fromSSELine: startLine), [.toolCall(index: 0, id: "call_1", name: "calculator", arguments: "{\"expression\":\"1+")])
        XCTAssertEqual(ChatService.events(fromSSELine: endLine), [.toolCall(index: 0, id: nil, name: nil, arguments: "2\"}")])
    }

    func testProviderStreamParserExtractsTextDelta() throws {
        let line = try makeSSE(["choices": [["delta": ["content": "hello"], "finish_reason": NSNull()]]])
        XCTAssertEqual(ChatService.events(fromSSELine: line), [.text("hello")])
    }

    func testToolExecutorRunsOnlyTheAllowlistedCalculator() {
        let call = ToolCall(id: "call_1", function: .init(name: "calculator", arguments: "{\"expression\":\"2 + 3 * 4\"}"))
        XCTAssertEqual(ToolExecutor.execute(call), "14")

        let unknown = ToolCall(id: "call_2", function: .init(name: "open_url", arguments: "{\"url\":\"https://example.com\"}"))
        XCTAssertEqual(ToolExecutor.execute(unknown), "That tool is unavailable; no action was taken.")
    }

    func testToolExecutorRejectsOversizedMalformedAndOverlongArguments() {
        let oversized = ToolCall(id: "call_large", function: .init(name: "calculator", arguments: String(repeating: " ", count: 1_025)))
        XCTAssertEqual(ToolExecutor.execute(oversized), "Calculator arguments were too large; no calculation was run.")

        let malformed = ToolCall(id: "call_bad", function: .init(name: "calculator", arguments: "not-json"))
        XCTAssertEqual(ToolExecutor.execute(malformed), "The calculator requires a JSON string field named expression.")

        let expression = String(repeating: "1", count: 257)
        let overlong = ToolCall(id: "call_long", function: .init(name: "calculator", arguments: "{\"expression\":\"\(expression)\"}"))
        XCTAssertEqual(ToolExecutor.execute(overlong), "The calculator rejected that expression.")
    }

    private func makeSSE(_ payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return "data: " + String(decoding: data, as: UTF8.self)
    }
}
