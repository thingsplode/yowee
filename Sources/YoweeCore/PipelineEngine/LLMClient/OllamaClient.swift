import Foundation
import os

private let osLog = Logger(subsystem: "com.yowee.app", category: "Ollama")

public final class OllamaClient: LLMClient {
    private let baseURL: String
    private let session: URLSession
    /// When true, passes "think": false in the request body — disables chain-of-thought
    /// on models that support it (e.g. deepseek-r1, qwq). Has no effect on other models.
    private let thinkingDisabled: Bool

    public init(
        baseURL: String = "http://localhost:11434",
        session: URLSession = .shared,
        thinkingDisabled: Bool = false
    ) {
        self.baseURL = baseURL
        self.session = session
        self.thinkingDisabled = thinkingDisabled
    }

    public func complete(system: String?, user: String, model: String, maxTokens: Int = 4096) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw LLMError.invalidURL
        }
        // 120s: Ollama must load the model into memory on first use, which can take 30–60s
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var messages: [[String: String]] = []
        if let system { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": user])

        var body: [String: Any] = ["model": model, "messages": messages, "stream": false]
        if thinkingDisabled { body["think"] = false }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        osLog.debug("complete: model=\(model, privacy: .public) think=\(self.thinkingDisabled ? "off" : "on", privacy: .public)")
        let start = Date()

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            let elapsed = Int(-start.timeIntervalSinceNow)
            osLog.error("network error after \(elapsed, privacy: .public)s: \(urlError.localizedDescription, privacy: .public)")
            throw networkError(urlError)
        }

        let elapsed = Int(-start.timeIntervalSinceNow)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.apiError(statusCode: -1, body: "")
        }
        osLog
            .debug(
                "response: status=\(http.statusCode, privacy: .public) elapsed=\(elapsed, privacy: .public)s bytes=\(data.count, privacy: .public)"
            )
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.apiError(statusCode: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        guard !decoded.message.content.isEmpty else { throw LLMError.emptyResponse }
        return decoded.message.content
    }

    public func fetchModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw LLMError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw networkError(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.apiError(statusCode: -1, body: "")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.apiError(statusCode: http.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models.map(\.name).sorted()
    }

    private func networkError(_ urlError: URLError) -> LLMError {
        switch urlError.code {
        case .timedOut:
            .apiError(
                statusCode: 0,
                body: "Ollama timed out. The model may still be loading — try again, or run `ollama pull <model>` first."
            )
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            .apiError(statusCode: 0, body: "Cannot connect to Ollama at \(baseURL). Run `ollama serve` to start it.")
        default:
            .apiError(statusCode: 0, body: urlError.localizedDescription)
        }
    }
}

private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable { let name: String }
    let models: [Model]
}

private struct OllamaResponse: Decodable {
    struct Message: Decodable { let content: String }
    let message: Message
}
