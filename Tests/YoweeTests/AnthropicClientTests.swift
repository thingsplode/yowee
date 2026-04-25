import Testing
@testable import YoweeCore

@Suite("AnthropicClient")
struct AnthropicClientTests {

    // MARK: - Helpers

    private static let successJSON = "{\"content\": [{\"text\": \"ok\"}]}"

    private func makeClient(
        apiKey: String = "test-key",
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> AnthropicClient {
        AnthropicClient(apiKey: apiKey, session: MockURLProtocol.makeSession(handler: handler))
    }

    private func makeClient(apiKey: String = "test-key", json: String = successJSON, statusCode: Int = 200) -> AnthropicClient {
        AnthropicClient(apiKey: apiKey, session: MockURLProtocol.makeSession(json: json, statusCode: statusCode))
    }

    private func jsonResponse(_ text: String) -> String {
        "{\"content\": [{\"text\": \"\(text)\"}]}"
    }

    private func okHTTP(_ request: URLRequest, json: String = successJSON) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, json.data(using: .utf8)!)
    }

    // MARK: Happy path

    @Test func successReturnsFirstContentText() async throws {
        let client = makeClient(json: jsonResponse("Hello, world!"))
        let result = try await client.complete(system: nil, user: "hi", model: "claude-sonnet-4-6", maxTokens: 100)
        #expect(result == "Hello, world!")
    }

    @Test func returnsFirstContentItemWhenMultiplePresent() async throws {
        let client = makeClient(json: "{\"content\": [{\"text\": \"first\"}, {\"text\": \"second\"}]}")
        let result = try await client.complete(system: nil, user: "hi", model: "claude-sonnet-4-6", maxTokens: 100)
        #expect(result == "first")
    }

    // MARK: Request construction

    @Test func sendsPostMethod() async throws {
        var capturedMethod: String?
        let client = makeClient { [self] request in
            capturedMethod = request.httpMethod
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "m", maxTokens: 100)
        #expect(capturedMethod == "POST")
    }

    @Test func sendsToCorrectEndpoint() async throws {
        var capturedURL: URL?
        let client = makeClient { [self] request in
            capturedURL = request.url
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "m", maxTokens: 100)
        #expect(capturedURL?.absoluteString == "https://api.anthropic.com/v1/messages")
    }

    @Test func sendsAPIKeyHeader() async throws {
        var capturedKey: String?
        let client = makeClient(apiKey: "sk-test-abc123") { [self] request in
            capturedKey = request.value(forHTTPHeaderField: "x-api-key")
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "m", maxTokens: 100)
        #expect(capturedKey == "sk-test-abc123")
    }

    @Test func sendsAnthropicVersionHeader() async throws {
        var capturedVersion: String?
        let client = makeClient { [self] request in
            capturedVersion = request.value(forHTTPHeaderField: "anthropic-version")
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "m", maxTokens: 100)
        #expect(capturedVersion == "2023-06-01")
    }

    @Test func sendsJSONContentTypeHeader() async throws {
        var capturedContentType: String?
        let client = makeClient { [self] request in
            capturedContentType = request.value(forHTTPHeaderField: "content-type")
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "m", maxTokens: 100)
        #expect(capturedContentType == "application/json")
    }

    @Test func requestBodyIncludesModelAndMaxTokens() async throws {
        var body: [String: Any] = [:]
        let client = makeClient { [self] request in
            body = (try? request.decodedJSONBody()) ?? [:]
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "claude-opus-4-7", maxTokens: 512)
        #expect(body["model"] as? String == "claude-opus-4-7")
        #expect(body["max_tokens"] as? Int == 512)
    }

    @Test func requestBodyIncludesUserMessage() async throws {
        var body: [String: Any] = [:]
        let client = makeClient { [self] request in
            body = (try? request.decodedJSONBody()) ?? [:]
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "translate this", model: "m", maxTokens: 100)
        let messages = body["messages"] as? [[String: String]]
        #expect(messages?.first?["role"] == "user")
        #expect(messages?.first?["content"] == "translate this")
    }

    @Test func includesSystemFieldWhenProvided() async throws {
        var body: [String: Any] = [:]
        let client = makeClient { [self] request in
            body = (try? request.decodedJSONBody()) ?? [:]
            return okHTTP(request)
        }
        _ = try await client.complete(system: "You are helpful", user: "hi", model: "m", maxTokens: 100)
        #expect(body["system"] as? String == "You are helpful")
    }

    @Test func omitsSystemFieldWhenNil() async throws {
        var body: [String: Any] = [:]
        let client = makeClient { [self] request in
            body = (try? request.decodedJSONBody()) ?? [:]
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "m", maxTokens: 100)
        #expect(body["system"] == nil)
    }

    // MARK: Error handling

    @Test func throwsAPIErrorOn401() async throws {
        let client = makeClient(json: "{\"error\": \"unauthorized\"}", statusCode: 401)
        await #expect(throws: LLMError.self) {
            try await client.complete(system: nil, user: "hi", model: "m", maxTokens: 100)
        }
    }

    @Test func throwsAPIErrorOn500WithBody() async throws {
        let client = makeClient(json: "{\"error\": \"server error\"}", statusCode: 500)
        do {
            _ = try await client.complete(system: nil, user: "hi", model: "m", maxTokens: 100)
            Issue.record("Expected error not thrown")
        } catch let error as LLMError {
            if case .apiError(let code, let body) = error {
                #expect(code == 500)
                #expect(body.contains("server error"))
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        }
    }

    @Test func throwsEmptyResponseWhenContentArrayEmpty() async throws {
        let client = makeClient(json: "{\"content\": []}")
        await #expect(throws: LLMError.self) {
            try await client.complete(system: nil, user: "hi", model: "m", maxTokens: 100)
        }
    }

    @Test func throwsEmptyResponseWhenTextIsEmpty() async throws {
        let client = makeClient(json: "{\"content\": [{\"text\": \"\"}]}")
        await #expect(throws: LLMError.self) {
            try await client.complete(system: nil, user: "hi", model: "m", maxTokens: 100)
        }
    }

    @Test func propagatesNetworkError() async throws {
        let client = AnthropicClient(apiKey: "k", session: MockURLProtocol.makeSession(error: URLError(.notConnectedToInternet)))
        await #expect(throws: (any Error).self) {
            try await client.complete(system: nil, user: "hi", model: "m", maxTokens: 100)
        }
    }
}
