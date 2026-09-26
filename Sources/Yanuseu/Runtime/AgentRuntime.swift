import Foundation

// The iPhone owns the turn. The provider is only an inference transport; tools run locally.
struct AgentTurnConfiguration {
    var model: String
    var baseURL: String
    var apiKey: String
    var calculatorEnabled: Bool
    var instructions: String
}

protocol AgentProvider {
    func stream(messages: [ChatMessage], configuration: AgentTurnConfiguration) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

struct DirectAgentProvider: AgentProvider {
    func stream(messages: [ChatMessage], configuration: AgentTurnConfiguration) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        ChatService.stream(messages: messages, model: configuration.model, baseURL: configuration.baseURL,
                           apiKey: configuration.apiKey, calculatorEnabled: configuration.calculatorEnabled,
                           instructions: configuration.instructions)
    }
}

protocol AgentTool {
    func execute(_ call: ToolCall, calculatorEnabled: Bool) -> String
}

struct NativeAgentTool: AgentTool {
    func execute(_ call: ToolCall, calculatorEnabled: Bool) -> String {
        ToolExecutor.execute(call, calculatorEnabled: calculatorEnabled)
    }
}

enum AgentRuntimeEvent: Equatable {
    case text(String)
    case message(ChatMessage)
    case cancelled(String)
}

private struct ToolCallFragment {
    var id = ""
    var name = ""
    var arguments = ""
}

enum AgentRuntimeError: LocalizedError {
    case incompleteToolCall
    case emptyResponse
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .incompleteToolCall: return "The provider returned an incomplete tool request; nothing was executed."
        case .emptyResponse: return "The provider completed the request without returning a text response."
        case .persistenceFailed: return "Could not save the tool request on this iPhone; no tool was run."
        }
    }
}

@MainActor
struct AgentRuntime {
    let provider: any AgentProvider
    let tool: any AgentTool

    init(provider: any AgentProvider = DirectAgentProvider(), tool: any AgentTool = NativeAgentTool()) {
        self.provider = provider
        self.tool = tool
    }

    // Emits completed transcript entries in order; the caller persists each before the next round.
    func run(messages: [ChatMessage], configuration: AgentTurnConfiguration,
             onEvent: @MainActor (AgentRuntimeEvent) async throws -> Void) async throws {
        var history = messages
        var partial = ""
        do {
            for round in 0..<4 {
                try Task.checkCancellation()
                partial = ""
                var fragments: [Int: ToolCallFragment] = [:]
                for try await event in provider.stream(messages: history, configuration: configuration) {
                    try Task.checkCancellation()
                    switch event {
                    case .text(let token):
                        partial += token
                        try await onEvent(.text(partial))
                    case .toolCall(let index, let id, let name, let arguments):
                        var fragment = fragments[index] ?? ToolCallFragment()
                        fragment.id += id ?? ""
                        fragment.name += name ?? ""
                        fragment.arguments += arguments ?? ""
                        fragments[index] = fragment
                    case .finished:
                        break
                    }
                }
                try Task.checkCancellation()
                let calls = try fragments.keys.sorted().map { index -> ToolCall in
                    guard let fragment = fragments[index], !fragment.id.isEmpty, !fragment.name.isEmpty else {
                        throw AgentRuntimeError.incompleteToolCall
                    }
                    return ToolCall(id: fragment.id, function: .init(name: fragment.name, arguments: fragment.arguments))
                }
                if calls.isEmpty {
                    guard !partial.isEmpty else { throw AgentRuntimeError.emptyResponse }
                    try await onEvent(.message(ChatMessage(role: .assistant, content: partial)))
                    return
                }
                if round == 3 {
                    try await onEvent(.message(ChatMessage(role: .assistant, content: "I stopped after four tool rounds for safety. You can continue with another message.")))
                    return
                }
                let assistant = ChatMessage(role: .assistant, content: partial, toolCalls: calls)
                history.append(assistant)
                try await onEvent(.message(assistant))
                try Task.checkCancellation()
                for (index, call) in calls.enumerated() {
                    try Task.checkCancellation()
                    let result = index < 4
                        ? tool.execute(call, calculatorEnabled: configuration.calculatorEnabled)
                        : "Tool call limit reached; no action was taken."
                    let reply = ChatMessage(role: .tool, content: result, toolCallID: call.id, toolName: call.function.name)
                    history.append(reply)
                    try await onEvent(.message(reply))
                }
            }
        } catch is CancellationError {
            try await onEvent(.cancelled(partial))
        }
    }
}
