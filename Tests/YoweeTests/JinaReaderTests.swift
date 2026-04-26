import Testing
@testable import YoweeCore

@Suite("JinaReader")
struct JinaReaderTests {

    private func makeReader(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> JinaReader {
        JinaReader(session: MockURLProtocol.makeSession(handler: handler))
    }

    private func okHTTP(_ request: URLRequest, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, body.data(using: .utf8)!)
    }

    // MARK: Happy path

    @Test func returnsMarkdownForValidURL() async {
        let reader = makeReader { [self] req in
            return okHTTP(req, body: "# Page Title\n\nSome content here.")
        }
        let result = await reader.fetchMarkdown(url: "https://example.com/article")
        #expect(result == "# Page Title\n\nSome content here.")
    }

    @Test func fetchesViaJinaReaderEndpoint() async {
        var capturedURL: URL?
        let reader = makeReader { [self] req in
            capturedURL = req.url
            return okHTTP(req, body: "content")
        }
        _ = await reader.fetchMarkdown(url: "https://example.com/page")
        #expect(capturedURL?.absoluteString.hasPrefix("https://r.jina.ai/") == true)
        #expect(capturedURL?.absoluteString.contains("example.com") == true)
    }

    // MARK: Graceful failure

    @Test func returnsNilOn404() async {
        let reader = JinaReader(session: MockURLProtocol.makeSession { req in
            let response = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        })
        let result = await reader.fetchMarkdown(url: "https://example.com/missing")
        #expect(result == nil)
    }

    @Test func returnsNilOnNetworkError() async {
        let reader = JinaReader(session: MockURLProtocol.makeSession(error: URLError(.notConnectedToInternet)))
        let result = await reader.fetchMarkdown(url: "https://example.com/page")
        #expect(result == nil)
    }

    @Test func returnsNilForEmptyBody() async {
        let reader = makeReader { req in
            let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let result = await reader.fetchMarkdown(url: "https://example.com/empty")
        #expect(result == nil)
    }
}
