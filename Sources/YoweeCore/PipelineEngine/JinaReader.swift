import Foundation

public struct JinaReader: Sendable {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches the given URL via Jina Reader and returns the page content as Markdown.
    /// Returns nil on network errors or non-2xx responses (so callers can fall back gracefully).
    public func fetchMarkdown(url: String) async -> String? {
        let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url
        guard let jinaURL = URL(string: "https://r.jina.ai/\(encoded)") else { return nil }
        var request = URLRequest(url: jinaURL)
        request.timeoutInterval = 30
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode)
        else { return nil }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.isEmpty ? nil : text
    }
}
