import XCTest
@testable import Yanuseu

final class ProviderConfigurationTests: XCTestCase {
    func testModelsEndpointAppendsModelsToVersionedBaseURL() throws {
        let endpoint = try ProviderConfiguration.modelsEndpoint(from: "https://api.example.com/v1/")
        XCTAssertEqual(endpoint.absoluteString, "https://api.example.com/v1/models")
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
