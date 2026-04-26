import Foundation

public struct TavilyResult: Sendable {
    public let url: String
    public let title: String
    public let content: String

    public init(url: String, title: String, content: String) {
        self.url = url
        self.title = title
        self.content = content
    }
}

public struct TavilyClient: Sendable {
    public let apiKey: String
    public let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func search(query: String, maxResults: Int = 5, depth: String = "basic") async throws -> [TavilyResult] {
        guard let url = URL(string: "https://api.tavily.com/search") else {
            throw LLMError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "api_key": apiKey,
            "query": query,
            "max_results": maxResults,
            "search_depth": depth,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.emptyResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.apiError(statusCode: http.statusCode, body: body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]]
        else {
            throw LLMError.emptyResponse
        }

        return results.compactMap { result in
            guard let url = result["url"] as? String else { return nil }
            let title = result["title"] as? String ?? ""
            let content = result["content"] as? String ?? ""
            return TavilyResult(url: url, title: title, content: content)
        }
    }
}
