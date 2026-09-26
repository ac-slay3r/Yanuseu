import XCTest
@testable import Yanuseu

final class ProviderConfigurationTests: XCTestCase {
    func testModelsEndpointAppendsModelsToVersionedBaseURL() throws {
        let endpoint = try ProviderConfiguration.modelsEndpoint(from: "https://api.example.com/v1/")
        XCTAssertEqual(endpoint.absoluteString, "https://api.example.com/v1/models")
    }

    func testModelResponseIDsAreSortedAndDeduplicated() throws {
        let data = try JSONSerialization.data(withJSONObject: ["data": [
            ["id": "model-z"], ["id": "model-a"], ["id": "model-z"], ["name": "missing-id"]
        ]])
        XCTAssertEqual(try ProviderConfiguration.parseModelIDs(from: data), ["model-a", "model-z"])
    }

    func testModelResponseRejectsUnexpectedSchema() throws {
        let data = try JSONSerialization.data(withJSONObject: ["models": [["id": "model-a"]]])
        XCTAssertThrowsError(try ProviderConfiguration.parseModelIDs(from: data))
    }

    func testModelResponseLimitsReturnedIDsToTwoHundred() throws {
        let models = (0..<205).map { ["id": String(format: "model-%03d", $0)] }
        let data = try JSONSerialization.data(withJSONObject: ["data": models])
        let ids = try ProviderConfiguration.parseModelIDs(from: data)
        XCTAssertEqual(ids.count, 200)
        XCTAssertEqual(ids.first, "model-000")
        XCTAssertEqual(ids.last, "model-199")
    }

    func testFetchModelsRejectsEmptyAPIKeyBeforeNetworkRequest() async {
        do {
            _ = try await ProviderConfiguration.fetchModelIDs(baseURL: "https://api.example.com/v1", apiKey: "  ")
            XCTFail("Expected an empty API key to be rejected")
        } catch let error as ProviderConfiguration.ProviderError {
            guard case .emptyAPIKey = error else { return XCTFail("Unexpected error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testChatEndpointAppendsChatCompletionsToVersionedBaseURL() throws {
        let endpoint = try ProviderConfiguration.chatCompletionsEndpoint(from: "https://api.example.com/v1")
        XCTAssertEqual(endpoint.absoluteString, "https://api.example.com/v1/chat/completions")
    }

    func testModelsEndpointRejectsInsecureHTTP() {
        XCTAssertThrowsError(try ProviderConfiguration.modelsEndpoint(from: "http://api.example.com/v1"))
    }

    func testModelsEndpointRejectsCredentialsAndQueryInBaseURL() {
        XCTAssertThrowsError(try ProviderConfiguration.modelsEndpoint(from: "https://user:pass@api.example.com/v1?key=x"))
    }

    func testSSEParserExtractsContentDelta() {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}"
        XCTAssertEqual(ChatService.events(fromSSELine: line), [.text("hello")])
    }

    func testSSEParserIgnoresDoneMarkerAndNonDataLines() {
        XCTAssertEqual(ChatService.events(fromSSELine: "data: [DONE]"), [.finished(nil)])
        XCTAssertEqual(ChatService.events(fromSSELine: "event: message"), [])
    }

    func testConnectionRejectsEmptyModelBeforeNetworkRequest() async {
        do {
            try await ProviderConfiguration.verifyConnection(baseURL: "https://api.example.com/v1", model: "  ", apiKey: "test-key")
            XCTFail("Expected an empty model to be rejected")
        } catch let error as ProviderConfiguration.ProviderError {
            guard case .emptyModel = error else { return XCTFail("Unexpected error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
