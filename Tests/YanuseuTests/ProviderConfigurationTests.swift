import XCTest
@testable import Yanuseu

final class ProviderConfigurationTests: XCTestCase {
    func testModelsEndpointAppendsModelsToVersionedBaseURL() throws {
        let endpoint = try ProviderConfiguration.modelsEndpoint(from: "https://api.example.com/v1/")
        XCTAssertEqual(endpoint.absoluteString, "https://api.example.com/v1/models")
    }

    func testModelsEndpointHandlesHostOnlyURL() throws {
        let endpoint = try ProviderConfiguration.modelsEndpoint(from: "https://api.example.com")
        XCTAssertEqual(endpoint.absoluteString, "https://api.example.com/models")
    }

    func testModelsEndpointRejectsInsecureHTTP() {
        XCTAssertThrowsError(try ProviderConfiguration.modelsEndpoint(from: "http://api.example.com/v1"))
    }

    func testModelsEndpointRejectsCredentialsAndQueryInBaseURL() {
        XCTAssertThrowsError(try ProviderConfiguration.modelsEndpoint(from: "https://user:pass@api.example.com/v1?key=x"))
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
