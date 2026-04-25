import Foundation

public protocol LLMClient {
    func complete(system: String?, user: String, model: String, maxTokens: Int) async throws -> String
}

public enum LLMError: Error, LocalizedError {
    case apiError(statusCode: Int, body: String)
    case emptyResponse
    case invalidURL
    case timeout

    public var errorDescription: String? {
        switch self {
        case .apiError(let code, let body) where code == 401:
            "API key rejected (401)\(body.isEmpty ? "" : ": \(body)")"
        case .apiError(let code, _) where code == 429:
            "Rate limit hit (429). Wait a moment and try again."
        case .apiError(let code, let body):
            "API error \(code): \(body.prefix(120))"
        case .emptyResponse: "The model returned an empty response"
        case .invalidURL: "Invalid API endpoint URL"
        case .timeout: "Request timed out after 30 seconds"
        }
    }
}
