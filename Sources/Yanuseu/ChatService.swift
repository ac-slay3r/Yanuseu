import Foundation

struct ChatService {
    enum ServiceError: LocalizedError {
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .httpStatus(let code): return "The provider returned HTTP \(code). Check its API settings."
            }
        }
    }

    static func stream(messages: [ChatMessage], model: String, baseURL: String, apiKey: String) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let endpoint = try ProviderConfiguration.chatCompletionsEndpoint(from: baseURL)
                    let payload: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": apiMessages(from: messages),
                        "tools": calculatorTools,
                        "tool_choice": "auto"
                    ]
                    var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.httpShouldSetCookies = false
                    configuration.urlCache = nil
                    let session = URLSession(configuration: configuration, delegate: ProviderRedirectBlocker(), delegateQueue: nil)
                    defer { session.invalidateAndCancel() }

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    guard (200..<300).contains(response.statusCode) else { throw ServiceError.httpStatus(response.statusCode) }
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw CancellationError() }
                        for event in events(fromSSELine: line) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    static func events(fromSSELine line: String) -> [ChatStreamEvent] {
        guard line.hasPrefix("data:") else { return [] }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return [.finished(nil)] }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let choice = choices.first else { return [] }

        var result: [ChatStreamEvent] = []
        if let delta = choice["delta"] as? [String: Any] {
            if let text = delta["content"] as? String, !text.isEmpty { result.append(.text(text)) }
            if let calls = delta["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    guard let index = call["index"] as? Int else { continue }
                    let function = call["function"] as? [String: Any]
                    result.append(.toolCall(
                        index: index,
                        id: call["id"] as? String,
                        name: function?["name"] as? String,
                        arguments: function?["arguments"] as? String
                    ))
                }
            }
        }
        if let finishReason = choice["finish_reason"] as? String { result.append(.finished(finishReason)) }
        return result
    }

    private static func apiMessages(from messages: [ChatMessage]) -> [[String: Any]] {
        let systemMessage: [String: Any] = [
            "role": "system",
            "content": "You may use one local tool named calculator for basic arithmetic. It evaluates arithmetic only and has no network, filesystem, or other side effects. Use the returned result accurately; never imply other tools or actions are available."
        ]
        var recent = Array(messages.suffix(40))
        while let first = recent.first, first.role != .user { recent.removeFirst() }
        let encoded = recent.map { message -> [String: Any] in
            var result: [String: Any] = ["role": message.role.rawValue, "content": message.content]
            if let toolCallID = message.toolCallID { result["tool_call_id"] = toolCallID }
            if let toolName = message.toolName { result["name"] = toolName }
            if let calls = message.toolCalls, !calls.isEmpty {
                result["tool_calls"] = calls.map { call in
                    [
                        "id": call.id,
                        "type": call.type,
                        "function": ["name": call.function.name, "arguments": call.function.arguments]
                    ] as [String: Any]
                }
            }
            if message.role == .assistant, message.content.isEmpty, message.toolCalls?.isEmpty == false {
                result["content"] = NSNull()
            }
            return result
        }
        return [systemMessage] + encoded
    }

    private static var calculatorTools: [[String: Any]] {
        [[
            "type": "function",
            "function": [
                "name": "calculator",
                "description": "Evaluate a basic arithmetic expression. Supports numbers, parentheses, +, -, *, and /.",
                "parameters": [
                    "type": "object",
                    "properties": ["expression": ["type": "string", "description": "Arithmetic expression only"]],
                    "required": ["expression"],
                    "additionalProperties": false
                ]
            ]
        ]]
    }
}

enum ChatStreamEvent: Equatable {
    case text(String)
    case toolCall(index: Int, id: String?, name: String?, arguments: String?)
    case finished(String?)
}

private final class ProviderRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
