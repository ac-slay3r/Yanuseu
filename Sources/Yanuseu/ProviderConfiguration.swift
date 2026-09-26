import Foundation

/// Validation and endpoint construction for OpenAI-compatible providers.
enum ProviderConfiguration {
    enum ProviderError: LocalizedError {
        case invalidEndpoint
        case emptyAPIKey
        case emptyModel
        case rejected(status: Int)
        case invalidModelResponse
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
            case .invalidModelResponse:
                return "The provider returned an unsupported models response. Enter the model ID manually."
            case .network:
                return "Could not reach the provider. Check the URL and your connection."
            }
        }
    }

    static func modelsEndpoint(from rawValue: String) throws -> URL {
        try endpoint(from: rawValue, suffix: "models")
    }

    static func chatCompletionsEndpoint(from rawValue: String) throws -> URL {
        try endpoint(from: rawValue, suffix: "chat/completions")
    }

    private static func endpoint(from rawValue: String, suffix: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw ProviderError.invalidEndpoint
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, suffix].filter { !$0.isEmpty }.joined(separator: "/")
        guard let endpoint = components.url else { throw ProviderError.invalidEndpoint }
        return endpoint
    }

    static func parseModelIDs(from data: Data) throws -> [String] {
        guard data.count <= 1_000_000,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["data"] as? [[String: Any]] else {
            throw ProviderError.invalidModelResponse
        }
        let ids = models.compactMap { item -> String? in
            guard let id = item["id"] as? String, !id.isEmpty, id.count <= 256 else { return nil }
            return id
        }
        return Array(Set(ids)).sorted().prefix(200).map { $0 }
    }

    static func fetchModelIDs(baseURL: String, apiKey: String) async throws -> [String] {
        let cleanedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedKey.isEmpty else { throw ProviderError.emptyAPIKey }
        let endpoint = try modelsEndpoint(from: baseURL)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(cleanedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: ProviderRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw ProviderError.network }
            guard (200..<300).contains(response.statusCode) else { throw ProviderError.rejected(status: response.statusCode) }
            return try parseModelIDs(from: data)
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.network
        }
    }

    static func verifyConnection(baseURL: String, model: String, apiKey: String) async throws {
        let cleanedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedKey.isEmpty else { throw ProviderError.emptyAPIKey }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProviderError.emptyModel }

        let endpoint = try modelsEndpoint(from: baseURL)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(cleanedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: ProviderRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw ProviderError.network }
            guard (200..<300).contains(response.statusCode) else { throw ProviderError.rejected(status: response.statusCode) }
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.network
        }
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
