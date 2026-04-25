import Testing
@testable import YoweeCore

@Suite("OllamaClient")
struct OllamaClientTests {

    // MARK: - Helpers

    private static let successJSON = "{\"message\": {\"content\": \"Hello from Ollama\", \"role\": \"assistant\"}}"

    private func makeClient(
        baseURL: String = "http://localhost:11434",
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> OllamaClient {
        OllamaClient(baseURL: baseURL, session: MockURLProtocol.makeSession(handler: handler))
    }

    private func makeClient(
        baseURL: String = "http://localhost:11434",
        json: String = successJSON,
        statusCode: Int = 200
    ) -> OllamaClient {
        OllamaClient(baseURL: baseURL, session: MockURLProtocol.makeSession(json: json, statusCode: statusCode))
    }

    private func okHTTP(_ request: URLRequest, json: String = successJSON) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, json.data(using: .utf8)!)
    }

    // MARK: Happy path

    @Test func successReturnsMessageContent() async throws {
        let client = makeClient()
        let result = try await client.complete(system: nil, user: "hi", model: "llama3.2", maxTokens: 100)
        #expect(result == "Hello from Ollama")
    }

    // MARK: Request construction

    @Test func sendsToCorrectEndpoint() async throws {
        var capturedURL: URL?
        let client = makeClient { [self] request in
            capturedURL = request.url
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "llama3.2", maxTokens: 100)
        #expect(capturedURL?.absoluteString == "http://localhost:11434/api/chat")
    }

    @Test func customBaseURLIsUsed() async throws {
        var capturedURL: URL?
        let client = makeClient(baseURL: "http://192.168.1.10:11434") { [self] request in
            capturedURL = request.url
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "llama3.2", maxTokens: 100)
        #expect(capturedURL?.absoluteString == "http://192.168.1.10:11434/api/chat")
    }

    @Test func sendsNoAuthorizationHeader() async throws {
        var capturedAuth: String?
        let client = makeClient { [self] request in
            capturedAuth = request.value(forHTTPHeaderField: "Authorization")
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "llama3.2", maxTokens: 100)
        #expect(capturedAuth == nil)
    }

    @Test func requestBodySetsStreamFalse() async throws {
        var body: [String: Any] = [:]
        let client = makeClient { [self] request in
            body = (try? request.decodedJSONBody()) ?? [:]
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "llama3.2", maxTokens: 100)
        #expect(body["stream"] as? Bool == false)
    }

    @Test func requestBodyIncludesModel() async throws {
        var body: [String: Any] = [:]
        let client = makeClient { [self] request in
            body = (try? request.decodedJSONBody()) ?? [:]
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "mistral", maxTokens: 100)
        #expect(body["model"] as? String == "mistral")
    }

    @Test func includesSystemMessageWhenProvided() async throws {
        var messages: [[String: String]] = []
        let client = makeClient { [self] request in
            let body = (try? request.decodedJSONBody()) ?? [:]
            messages = body["messages"] as? [[String: String]] ?? []
            return okHTTP(request)
        }
        _ = try await client.complete(system: "You are helpful", user: "hi", model: "llama3.2", maxTokens: 100)
        #expect(messages.first?["role"] == "system")
        #expect(messages.first?["content"] == "You are helpful")
        #expect(messages.count == 2)
    }

    @Test func omitsSystemMessageWhenNil() async throws {
        var messages: [[String: String]] = []
        let client = makeClient { [self] request in
            let body = (try? request.decodedJSONBody()) ?? [:]
            messages = body["messages"] as? [[String: String]] ?? []
            return okHTTP(request)
        }
        _ = try await client.complete(system: nil, user: "hi", model: "llama3.2", maxTokens: 100)
        #expect(messages.count == 1)
        #expect(messages.first?["role"] == "user")
    }

    // MARK: Error handling

    @Test func throwsAPIErrorOnNon200() async throws {
        let client = makeClient(json: "{\"error\": \"model not found\"}", statusCode: 404)
        await #expect(throws: LLMError.self) {
            try await client.complete(system: nil, user: "hi", model: "nonexistent", maxTokens: 100)
        }
    }

    @Test func throwsEmptyResponseWhenContentEmpty() async throws {
        let client = makeClient(json: "{\"message\": {\"content\": \"\", \"role\": \"assistant\"}}")
        await #expect(throws: LLMError.self) {
            try await client.complete(system: nil, user: "hi", model: "llama3.2", maxTokens: 100)
        }
    }

    @Test func propagatesNetworkError() async throws {
        let client = OllamaClient(baseURL: "http://localhost:11434",
                                  session: MockURLProtocol.makeSession(error: URLError(.cannotConnectToHost)))
        await #expect(throws: (any Error).self) {
            try await client.complete(system: nil, user: "hi", model: "llama3.2", maxTokens: 100)
        }
    }
}
