import Testing
@testable import YoweeCore

private let tavilyJSON = """
{
    "results": [
        {"url": "https://example.com/a", "title": "Article A", "content": "Snippet A"},
        {"url": "https://example.com/b", "title": "Article B", "content": "Snippet B"}
    ]
}
"""

/// URLSession that routes Tavily and Jina requests to separate handlers.
private func makeResearchSession(
    tavilyResponse: String = tavilyJSON,
    tavilyStatus: Int = 200,
    jinaResponse: String = "# Full page content",
    jinaStatus: Int = 200
) -> URLSession {
    MockURLProtocol.makeSession { request in
        let url = request.url?.absoluteString ?? ""
        let status: Int
        let body: String
        if url.contains("tavily.com") {
            status = tavilyStatus
            body = tavilyResponse
        } else {
            status = jinaStatus
            body = jinaResponse
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (response, body.data(using: .utf8)!)
    }
}

@Suite("PipelineRunner — research step")
struct PipelineRunnerResearchTests {

    private func researchStep(
        tavilyKey: String = "tvly-test",
        maxResults: Int = 2,
        depth: String = "basic"
    ) -> StepData {
        StepData(
            stepKind: .research,
            tavilyKey: tavilyKey,
            tavilyMaxResults: maxResults,
            tavilySearchDepth: depth
        )
    }

    @Test func researchStepOutputContainsQuery() async throws {
        let runner = PipelineRunner(
            clientFactory: { _ in MockLLMClient(response: "unreachable") },
            session: makeResearchSession()
        )
        let result = try await runner.run(steps: [researchStep()], input: "coral reefs")
        #expect(result.contains("coral reefs"))
    }

    @Test func researchStepOutputContainsTitles() async throws {
        let runner = PipelineRunner(
            clientFactory: { _ in MockLLMClient(response: "unreachable") },
            session: makeResearchSession()
        )
        let result = try await runner.run(steps: [researchStep()], input: "oceans")
        #expect(result.contains("Article A"))
        #expect(result.contains("Article B"))
    }

    @Test func researchStepOutputContainsSourceURLs() async throws {
        let runner = PipelineRunner(
            clientFactory: { _ in MockLLMClient(response: "unreachable") },
            session: makeResearchSession()
        )
        let result = try await runner.run(steps: [researchStep()], input: "oceans")
        #expect(result.contains("https://example.com/a"))
        #expect(result.contains("https://example.com/b"))
    }

    @Test func researchStepUsesJinaContentWhenAvailable() async throws {
        let runner = PipelineRunner(
            clientFactory: { _ in MockLLMClient(response: "unreachable") },
            session: makeResearchSession(jinaResponse: "## Full Jina Markdown")
        )
        let result = try await runner.run(steps: [researchStep()], input: "topic")
        #expect(result.contains("Full Jina Markdown"))
    }

    @Test func researchStepFallsBackToSnippetWhenJinaFails() async throws {
        let runner = PipelineRunner(
            clientFactory: { _ in MockLLMClient(response: "unreachable") },
            session: makeResearchSession(jinaStatus: 404)
        )
        let result = try await runner.run(steps: [researchStep()], input: "topic")
        #expect(result.contains("Snippet A"))
        #expect(result.contains("Snippet B"))
    }

    @Test func researchOutputBecomesInputForNextStep() async throws {
        let runner = PipelineRunner(
            clientFactory: { _ in EchoClient() },
            session: makeResearchSession()
        )
        let steps: [StepData] = [
            researchStep(),
            StepData(systemPrompt: nil, userTemplate: "Summarize: {{input}}", provider: .anthropic, modelID: "m"),
        ]
        let result = try await runner.run(steps: steps, input: "reefs")
        #expect(result.hasPrefix("echo:Summarize:"))
        #expect(result.contains("Article A"))
    }

    @Test func researchStepThrowsWhenTavilyFails() async throws {
        let session = makeResearchSession(tavilyResponse: "{\"error\": \"unauthorized\"}", tavilyStatus: 401)
        let runner = PipelineRunner(
            clientFactory: { _ in MockLLMClient(response: "unreachable") },
            session: session
        )
        await #expect(throws: LLMError.self) {
            try await runner.run(steps: [researchStep()], input: "topic")
        }
    }

    @Test func queryTemplateIsRenderedBeforeSendingToTavily() async throws {
        var capturedBody: Data?
        let session = MockURLProtocol.makeSession { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("tavily.com") {
                capturedBody = request.httpBodyStream.flatMap { stream in
                    stream.open()
                    var data = Data()
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                    defer { buffer.deallocate() }
                    while stream.hasBytesAvailable {
                        let n = stream.read(buffer, maxLength: 4096)
                        if n > 0 { data.append(buffer, count: n) }
                    }
                    return data
                }
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, tavilyJSON.data(using: .utf8)!)
            } else {
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (resp, "page".data(using: .utf8)!)
            }
        }

        let step = StepData(
            stepKind: .research,
            queryTemplate: "Recent studies on {{input}} 2024",
            tavilyKey: "tvly-test",
            tavilyMaxResults: 2,
            tavilySearchDepth: "basic"
        )
        let runner = PipelineRunner(
            clientFactory: { _ in MockLLMClient(response: "unreachable") },
            session: session
        )
        _ = try await runner.run(steps: [step], input: "coral reefs")

        let body = try #require(capturedBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let query = json?["query"] as? String
        #expect(query == "Recent studies on coral reefs 2024")
    }
}
