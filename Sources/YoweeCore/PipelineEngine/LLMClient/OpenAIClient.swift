import Foundation

public final class OpenAIClient: LLMClient {
    private let apiKey: String
    private let baseURL: String
    private let session: URLSession
    /// "low", "medium", or "high". Only sent for o-series models; nil = API default.
    private let reasoningEffort: String?
    private let timeout: TimeInterval

    public init(
        apiKey: String,
        baseURL: String = "https://api.openai.com",
        session: URLSession = .shared,
        reasoningEffort: String? = nil,
        timeout: TimeInterval = 60
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
        self.reasoningEffort = reasoningEffort
        self.timeout = timeout
    }

    public func complete(system: String?, user: String, model: String, maxTokens: Int = 4096) async throws -> String {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw LLMError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var messages: [[String: String]] = []
        if let system { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": user])

        var body: [String: Any] = ["model": model, "messages": messages, "max_completion_tokens": maxTokens]
        // reasoning_effort is only supported by o-series models; sending it to others causes a 400.
        // "none" disables reasoning entirely on models that support it (e.g. o4-mini).
        if let effort = reasoningEffort, isReasoningModel(model) {
            body["reasoning_effort"] = effort
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .timedOut {
                throw LLMError.timeout(seconds: Int(timeout))
            }
            throw LLMError.apiError(statusCode: 0, body: urlError.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.apiError(statusCode: -1, body: "")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.apiError(statusCode: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        // content is String? — reasoning models can return null when they produce only
        // reasoning tokens with no visible output (e.g. reasoning_effort: "none" edge cases).
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw LLMError.emptyResponse
        }
        return text
    }

    public func fetchModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/v1/models") else {
            throw LLMError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.apiError(statusCode: -1, body: "")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.apiError(statusCode: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data
            .map(\.id)
            .filter(isChatModel)
            .sorted()
    }

    private func isReasoningModel(_ id: String) -> Bool {
        let prefixes = ["o1", "o2", "o3", "o4", "o5"]
        return prefixes.contains(where: { id.hasPrefix($0) })
    }

    private func isChatModel(_ id: String) -> Bool {
        let exclude = ["text-embedding", "dall-e", "whisper", "tts-", "babbage", "davinci", "curie", "ada", "text-moderation"]
        if exclude.contains(where: { id.hasPrefix($0) }) { return false }
        let include = ["gpt-", "o1", "o2", "o3", "o4", "o5", "chatgpt-"]
        return include.contains(where: { id.hasPrefix($0) })
    }
}

private struct OpenAIModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }

    let choices: [Choice]
}
