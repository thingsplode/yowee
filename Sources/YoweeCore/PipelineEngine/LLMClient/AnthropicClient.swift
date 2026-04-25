import Foundation

public final class AnthropicClient: LLMClient {
    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func complete(system: String?, user: String, model: String, maxTokens: Int = 4096) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw LLMError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": user]]
        ]
        if let system { body["system"] = system }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.apiError(statusCode: -1, body: "")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.apiError(statusCode: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let text = decoded.content.first?.text, !text.isEmpty else {
            throw LLMError.emptyResponse
        }
        return text
    }
}

private struct AnthropicResponse: Decodable {
    struct Content: Decodable { let text: String }
    let content: [Content]
}
