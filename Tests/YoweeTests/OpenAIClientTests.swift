import Testing
@testable import YoweeCore

@Suite("OpenAIClient")
struct OpenAIClientTests {

    // MARK: - Helpers

    private static let successJSON = "{\"choices\": [{\"message\": {\"content\": \"Hello from GPT\"}}]}"

    private func makeClient(
        apiKey: String = "test-key",
        baseURL: String = "https://api.openai.com",
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> OpenAIClient {
        OpenAIClient(apiKey: apiKey, baseURL: baseURL, session: MockURLProtocol.makeSession(handler: handler))
    }

    private func makeClient(
        apiKey: String = "test-key",
        baseURL: String = "https://api.openai.com",
        json: String = successJSON,
        statusCode: Int = 200
    ) -> OpenAIClient {
        OpenAIClient(apiKey: apiKey, baseURL: baseURL, session: MockURLProtocol.makeSession(json: json, statusCode: statusCode))
    }

    private func okHTTP(_ request: URLRequest, json: String = successJSON) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, json.data(using: .utf8)!)
    }

    // MARK: Happy path

    @Test func successReturnsFirstChoiceContent() async throws {
        let client = makeClient()
        let result = try await client.complete(system: nil, user: "hi", model: "gpt-4o", maxTokens: 100)
        #expect(result == "Hello from GPT")
    }

    @Test func returnsFirstChoiceWhenMultiplePresent() async throws {
        let client = makeClient(json: "{\"choices\": [{\"message\": {\"content\": \"first\"}}, {\"message\": {\"content\": \"second\"}}]}")
        let result = try await client.complete(system: nil, user: "hi", model: "gpt-4o", maxTokens: 100)
        #expect(result == "first")
    }

    // MARK: Request construction

    @Test func sendsToCorrectDefaultEndpoint() async throws {
        var capturedURL: URL?
        let client = makeClient { [self] request in
            capturedURL = request.url
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "gpt-4o", maxTokens: 100)
        #expect(capturedURL?.absoluteString == "https://api.openai.com/v1/chat/completions")
    }

    @Test func customBaseURLIsUsed() async throws {
        var capturedURL: URL?
        let client = makeClient(baseURL: "https://my-proxy.example.com") { [self] request in
            capturedURL = request.url
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "gpt-4o", maxTokens: 100)
        #expect(capturedURL?.absoluteString == "https://my-proxy.example.com/v1/chat/completions")
    }

    @Test func sendsBearerAuthHeader() async throws {
        var capturedAuth: String?
        let client = makeClient(apiKey: "sk-openai-xyz") { [self] request in
            capturedAuth = request.value(forHTTPHeaderField: "Authorization")
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "gpt-4o", maxTokens: 100)
        #expect(capturedAuth == "Bearer sk-openai-xyz")
    }

    @Test func requestBodyIncludesModelAndMaxTokens() async throws {
        var body: [String: Any] = [:]
        let client = makeClient { [self] request in
            body = (try? request.decodedJSONBody()) ?? [:]
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "gpt-4o-mini", maxTokens: 256)
        #expect(body["model"] as? String == "gpt-4o-mini")
        #expect(body["max_completion_tokens"] as? Int == 256)
    }

    @Test func includesSystemMessageWhenProvided() async throws {
        var messages: [[String: String]] = []
        let client = makeClient { [self] request in
            let body = (try? request.decodedJSONBody()) ?? [:]
            messages = body["messages"] as? [[String: String]] ?? []
            return okHTTP(request)
        }
        _ = try await client.complete(system: "Be concise", user: "hi", model: "gpt-4o", maxTokens: 100)
        #expect(messages.first?["role"] == "system")
        #expect(messages.first?["content"] == "Be concise")
        #expect(messages.last?["role"] == "user")
    }

    @Test func omitsSystemMessageWhenNil() async throws {
        var messages: [[String: String]] = []
        let client = makeClient { [self] request in
            let body = (try? request.decodedJSONBody()) ?? [:]
            messages = body["messages"] as? [[String: String]] ?? []
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "gpt-4o", maxTokens: 100)
        #expect(messages.count == 1)
        #expect(messages.first?["role"] == "user")
    }

    // MARK: Error handling

    @Test func throwsAPIErrorOnNon200() async throws {
        let client = makeClient(json: "{\"error\": {\"message\": \"invalid\"}}", statusCode: 400)
        await #expect(throws: LLMError.self) {
            try await client.complete(system: nil, user: "hi", model: "gpt-4o", maxTokens: 100)
        }
    }

    @Test func throwsEmptyResponseWhenChoicesEmpty() async throws {
        let client = makeClient(json: "{\"choices\": []}")
        await #expect(throws: LLMError.self) {
            try await client.complete(system: nil, user: "hi", model: "gpt-4o", maxTokens: 100)
        }
    }

    @Test func throwsEmptyResponseWhenContentEmpty() async throws {
        let client = makeClient(json: "{\"choices\": [{\"message\": {\"content\": \"\"}}]}")
        await #expect(throws: LLMError.self) {
            try await client.complete(system: nil, user: "hi", model: "gpt-4o", maxTokens: 100)
        }
    }

    @Test func throwsInvalidURLForMalformedBaseURL() async throws {
        let client = OpenAIClient(apiKey: "k", baseURL: "not a url ://broken",
                                  session: MockURLProtocol.makeSession(json: "{}"))
        do {
            _ = try await client.complete(system: nil, user: "hi", model: "gpt-4o", maxTokens: 100)
            Issue.record("Expected error not thrown")
        } catch LLMError.invalidURL {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func propagatesNetworkError() async throws {
        let client = OpenAIClient(apiKey: "k", session: MockURLProtocol.makeSession(error: URLError(.timedOut)))
        await #expect(throws: (any Error).self) {
            try await client.complete(system: nil, user: "hi", model: "gpt-4o", maxTokens: 100)
        }
    }
}
