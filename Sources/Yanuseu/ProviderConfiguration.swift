import Foundation

enum ProviderConfiguration {
    static func modelsEndpoint(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw ProviderError.invalidEndpoint
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = path.isEmpty ? "/models" : "/\(path)/models"
        guard let endpoint = components.url else { throw ProviderError.invalidEndpoint }
        return endpoint
    }

    enum ProviderError: LocalizedError {
        case invalidEndpoint
        case emptyAPIKey
        case emptyModel
        case rejected(status: Int)
        case network

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint:
                return "Enter a valid HTTPS OpenAI-compatible API base URL, such as https://api.openai.com/v1."
            case .emptyAPIKey:
                return "Enter your provider API key."
            case .emptyModel:
                return "Enter the model ID supplied by your provider."
            case .rejected(let status):
                return "The provider returned HTTP \(status). Check the endpoint and API key."
            case .network:
                return "Could not reach the provider. Check the URL and your connection."
            }
        }
    }

    static func verifyConnection(baseURL: String, model: String, apiKey: String) async throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.emptyAPIKey
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.emptyModel
        }
        let endpoint = try modelsEndpoint(from: baseURL)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw ProviderError.network }
            guard (200..<300).contains(response.statusCode) else {
                throw ProviderError.rejected(status: response.statusCode)
            }
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.network
        }
    }
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
