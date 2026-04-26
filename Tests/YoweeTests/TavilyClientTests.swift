import Testing
@testable import YoweeCore

@Suite("TavilyClient")
struct TavilyClientTests {

    private static let successJSON = """
    {
        "results": [
            {"url": "https://example.com/a", "title": "Article A", "content": "Summary of A"},
            {"url": "https://example.com/b", "title": "Article B", "content": "Summary of B"}
        ]
    }
    """

    private func makeClient(
        apiKey: String = "tvly-test",
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> TavilyClient {
        TavilyClient(apiKey: apiKey, session: MockURLProtocol.makeSession(handler: handler))
    }

    private func makeClient(apiKey: String = "tvly-test", json: String = successJSON, statusCode: Int = 200) -> TavilyClient {
        TavilyClient(apiKey: apiKey, session: MockURLProtocol.makeSession(json: json, statusCode: statusCode))
    }

    private func okHTTP(_ request: URLRequest, json: String = successJSON) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, json.data(using: .utf8)!)
    }

    // MARK: Happy path

    @Test func returnsResults() async throws {
        let client = makeClient()
        let results = try await client.search(query: "swift concurrency", maxResults: 2, depth: "basic")
        #expect(results.count == 2)
        #expect(results[0].url == "https://example.com/a")
        #expect(results[0].title == "Article A")
        #expect(results[0].content == "Summary of A")
    }

    @Test func emptyResultsArrayReturnsEmpty() async throws {
        let client = makeClient(json: "{\"results\": []}")
        let results = try await client.search(query: "nothing", maxResults: 5, depth: "basic")
        #expect(results.isEmpty)
    }

    // MARK: Request construction

    @Test func sendsPostToCorrectEndpoint() async throws {
        var capturedURL: URL?
        var capturedMethod: String?
        let client = makeClient { [self] req in
            capturedURL = req.url
            capturedMethod = req.httpMethod
            return okHTTP(req)
        }
        _ = try await client.search(query: "q", maxResults: 3, depth: "basic")
        #expect(capturedURL?.absoluteString == "https://api.tavily.com/search")
        #expect(capturedMethod == "POST")
    }

    @Test func requestBodyIncludesAllParams() async throws {
        var body: [String: Any] = [:]
        let client = makeClient { [self] req in
            body = (try? req.decodedJSONBody()) ?? [:]
            return okHTTP(req)
        }
        _ = try await client.search(query: "climate change", maxResults: 7, depth: "advanced")
        #expect(body["query"] as? String == "climate change")
        #expect(body["max_results"] as? Int == 7)
        #expect(body["search_depth"] as? String == "advanced")
        #expect(body["api_key"] as? String == "tvly-test")
    }

    @Test func sendsJSONContentType() async throws {
        var capturedContentType: String?
        let client = makeClient { [self] req in
            capturedContentType = req.value(forHTTPHeaderField: "content-type")
            return okHTTP(req)
        }
        _ = try await client.search(query: "q", maxResults: 1, depth: "basic")
        #expect(capturedContentType == "application/json")
    }

    // MARK: Error handling

    @Test func throwsAPIErrorOn401() async throws {
        let client = makeClient(json: "{\"error\": \"unauthorized\"}", statusCode: 401)
        await #expect(throws: LLMError.self) {
            try await client.search(query: "q", maxResults: 1, depth: "basic")
        }
    }

    @Test func throwsAPIErrorOn429WithBody() async throws {
        let client = makeClient(json: "{\"error\": \"rate limit\"}", statusCode: 429)
        do {
            _ = try await client.search(query: "q", maxResults: 1, depth: "basic")
            Issue.record("Expected error not thrown")
        } catch let error as LLMError {
            if case .apiError(let code, let body) = error {
                #expect(code == 429)
                #expect(body.contains("rate limit"))
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        }
    }

    @Test func throwsAPIErrorOn500() async throws {
        let client = makeClient(json: "{\"error\": \"server error\"}", statusCode: 500)
        await #expect(throws: LLMError.self) {
            try await client.search(query: "q", maxResults: 1, depth: "basic")
        }
    }

    @Test func throwsEmptyResponseWhenBodyMalformed() async throws {
        let client = makeClient(json: "not-json")
        await #expect(throws: LLMError.self) {
            try await client.search(query: "q", maxResults: 1, depth: "basic")
        }
    }

    @Test func propagatesNetworkError() async throws {
        let client = TavilyClient(apiKey: "k", session: MockURLProtocol.makeSession(error: URLError(.notConnectedToInternet)))
        await #expect(throws: (any Error).self) {
            try await client.search(query: "q", maxResults: 1, depth: "basic")
        }
    }
}
