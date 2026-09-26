import Foundation

struct ChatService {
    enum ServiceError: LocalizedError {
        case httpStatus(Int)
        case malformedEvent

        var errorDescription: String? {
            switch self {
            case .httpStatus(let code): return "The provider returned HTTP \(code). Check its API settings."
            case .malformedEvent: return "The provider sent an unreadable streaming response."
            }
        }
    }

    static func stream(messages: [ChatMessage], model: String, baseURL: String, apiKey: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let endpoint = try ProviderConfiguration.chatCompletionsEndpoint(from: baseURL)
                    let payload: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
                    ]
                    var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.httpShouldSetCookies = false
                    let session = URLSession(configuration: configuration, delegate: ProviderRedirectBlocker(), delegateQueue: nil)
                    defer { session.invalidateAndCancel() }

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let response = response as? HTTPURLResponse else { throw ServiceError.malformedEvent }
                    guard (200..<300).contains(response.statusCode) else { throw ServiceError.httpStatus(response.statusCode) }
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw CancellationError() }
                        if let token = contentDelta(fromSSELine: line) { continuation.yield(token) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    static func contentDelta(fromSSELine line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else { return nil }
        return delta["content"] as? String
    }
}

private final class ProviderRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
