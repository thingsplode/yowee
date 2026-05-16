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

        let body = TavilyRequest(apiKey: apiKey, query: query, maxResults: maxResults, searchDepth: depth)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.emptyResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.apiError(statusCode: http.statusCode, body: body)
        }

        let decoded: TavilyResponse
        do {
            decoded = try JSONDecoder().decode(TavilyResponse.self, from: data)
        } catch {
            throw LLMError.emptyResponse
        }
        return decoded.results.map { TavilyResult(url: $0.url, title: $0.title, content: $0.content) }
    }
}

// MARK: - Codable DTOs

private struct TavilyRequest: Encodable {
    let apiKey: String
    let query: String
    let maxResults: Int
    let searchDepth: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case query
        case maxResults = "max_results"
        case searchDepth = "search_depth"
    }
}

private struct TavilyResponse: Decodable {
    struct Result: Decodable {
        let url: String
        let title: String
        let content: String
    }
    let results: [Result]
}
