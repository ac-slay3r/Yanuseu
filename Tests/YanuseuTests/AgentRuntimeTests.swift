import XCTest
@testable import Yanuseu

@MainActor
final class AgentRuntimeTests: XCTestCase {
    private final class ScriptedProvider: AgentProvider {
        var replies: [[ChatStreamEvent]]
        var requests: [[ChatMessage]] = []
        init(_ replies: [[ChatStreamEvent]]) { self.replies = replies }
        func stream(messages: [ChatMessage], configuration: AgentTurnConfiguration) -> AsyncThrowingStream<ChatStreamEvent, Error> {
            requests.append(messages)
            let events = replies.removeFirst()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    private struct CalculatorTool: AgentTool {
        func execute(_ call: ToolCall, calculatorEnabled: Bool) -> String {
            ToolExecutor.execute(call, calculatorEnabled: calculatorEnabled)
        }
    }

    private let configuration = AgentTurnConfiguration(model: "example", baseURL: "https://example.com/v1", apiKey: "test", calculatorEnabled: true, instructions: "")

    func testStreamedToolResultContinuesWithOrderedContext() async throws {
        let provider = ScriptedProvider([
            [.text("Working "), .toolCall(index: 0, id: "call-1", name: "calculator", arguments: "{\"expression\":\"2"), .toolCall(index: 0, id: nil, name: nil, arguments: "+3\"}"), .finished("tool_calls")],
            [.text("Five."), .finished("stop")]
        ])
        let runtime = AgentRuntime(provider: provider, tool: CalculatorTool())
        let user = ChatMessage(role: .user, content: "Calculate 2+3")
        var events: [AgentRuntimeEvent] = []
        try await runtime.run(messages: [user], configuration: configuration) { events.append($0) }

        XCTAssertEqual(provider.requests.count, 2)
        XCTAssertEqual(provider.requests[1].map(\.role), [.user, .assistant, .tool])
        XCTAssertEqual(provider.requests[1][1].toolCalls?.first?.id, "call-1")
        XCTAssertEqual(provider.requests[1][1].content, "Working ")
        XCTAssertEqual(provider.requests[1][2].toolCallID, "call-1")
        XCTAssertEqual(provider.requests[1][2].content, "5")
        let roles: [ChatMessage.Role] = events.compactMap { event in
            if case .message(let message) = event { return message.role }
            return nil
        }
        XCTAssertEqual(roles, [.assistant, .tool, .assistant])
        if case .message(let last)? = events.last {
            XCTAssertEqual(last.content, "Five.")
        } else {
            XCTFail("Expected final assistant message")
        }
    }

    func testPersistenceFailureBeforeToolExecutionStopsTurn() async {
        let provider = ScriptedProvider([[.toolCall(index: 0, id: "c", name: "calculator", arguments: "{\"expression\":\"2+3\"}"), .finished(nil)]])
        let runtime = AgentRuntime(provider: provider, tool: CalculatorTool())
        do {
            try await runtime.run(messages: [ChatMessage(role: .user, content: "Calculate")], configuration: configuration) { event in
                if case .message(let message) = event, message.toolCalls != nil {
                    throw AgentRuntimeError.persistenceFailed
                }
            }
            XCTFail("Expected persistence failure")
        } catch AgentRuntimeError.persistenceFailed {
            XCTAssertEqual(provider.requests.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDisabledCalculatorNeverExecutes() async throws {
        let provider = ScriptedProvider([
            [.toolCall(index: 0, id: "c", name: "calculator", arguments: "{\"expression\":\"2+3\"}"), .finished(nil)],
            [.text("Done"), .finished(nil)]
        ])
        var config = configuration
        config.calculatorEnabled = false
        var replies: [ChatMessage] = []
        try await AgentRuntime(provider: provider).run(messages: [ChatMessage(role: .user, content: "Calculate")], configuration: config) { event in
            if case .message(let message) = event { replies.append(message) }
        }
        XCTAssertEqual(replies[1].role, .tool)
        XCTAssertTrue(replies[1].content.contains("disabled"))
        XCTAssertEqual(provider.requests.count, 2)
    }

    func testIncompleteToolCallFailsClosed() async {
        let provider = ScriptedProvider([[.toolCall(index: 0, id: nil, name: "calculator", arguments: "{}"), .finished(nil)]])
        do {
            try await AgentRuntime(provider: provider).run(messages: [ChatMessage(role: .user, content: "Calculate")], configuration: configuration) { _ in }
            XCTFail("Expected an incomplete-call error")
        } catch AgentRuntimeError.incompleteToolCall {
            XCTAssertEqual(provider.requests.count, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancelAfterFirstTokenKeepsPartialTextAndPreventsToolExecution() async throws {
        let provider = ScriptedProvider([[
            .text("Partial"), .toolCall(index: 0, id: "call-1", name: "calculator", arguments: "{\"expression\":\"2+3\"}"), .finished("tool_calls")
        ]])
        let runtime = AgentRuntime(provider: provider, tool: CalculatorTool())
        var events: [AgentRuntimeEvent] = []
        let task = Task {
            try await runtime.run(messages: [ChatMessage(role: .user, content: "Calculate")], configuration: configuration) { event in
                events.append(event)
                if event == .text("Partial") { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        try await task.value
        XCTAssertEqual(events.last, .cancelled("Partial"))
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertFalse(events.contains { if case .message(let message) = $0 { return message.role == .tool } else { return false } })
    }

    func testDisabledCalculatorIsRejectedByExecutorInContinuation() async throws {
        let provider = ScriptedProvider([
            [.toolCall(index: 0, id: "call-1", name: "calculator", arguments: "{\"expression\":\"2+3\"}"), .finished("tool_calls")],
            [.text("Unavailable"), .finished("stop")]
        ])
        let runtime = AgentRuntime(provider: provider, tool: CalculatorTool())
        var events: [AgentRuntimeEvent] = []
        var disabled = configuration
        disabled.calculatorEnabled = false
        try await runtime.run(messages: [ChatMessage(role: .user, content: "Calculate")], configuration: disabled) { events.append($0) }
        XCTAssertEqual(provider.requests[1][2].content, "Calculator is disabled in Agent Controls; no calculation was run.")
    }
}
