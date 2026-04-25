@_exported import Foundation

/// URLProtocol subclass that intercepts requests made by sessions created with makeSession(handler:).
/// Handlers are stored per-session (keyed by UUID injected into session config headers), so
/// concurrent tests can each have independent mocks without interfering with each other.
final class MockURLProtocol: URLProtocol {
    private static let sessionHeaderKey = "X-Mock-Session-ID"
    private static var handlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    private static let lock = NSLock()

    /// Creates a URLSession whose every request is handled by `handler`.
    static func makeSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let id = UUID().uuidString
        lock.lock(); handlers[id] = handler; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = [sessionHeaderKey: id]
        return URLSession(configuration: config)
    }

    /// Convenience: session that responds with static JSON at a given status code.
    static func makeSession(json: String, statusCode: Int = 200) -> URLSession {
        makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }
    }

    /// Convenience: session that fails with a URLError.
    static func makeSession(error: URLError) -> URLSession {
        makeSession { _ in throw error }
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.sessionHeaderKey) ?? ""
        Self.lock.lock()
        let handler = Self.handlers[id]
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Request body helper

extension URLRequest {
    /// Reads the request body from either httpBody or httpBodyStream (URLSession promotes it to a stream).
    func decodedJSONBody() throws -> [String: Any] {
        let data: Data
        if let body = httpBody {
            data = body
        } else if let stream = httpBodyStream {
            var accumulated = Data()
            stream.open()
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(buf, maxLength: 4096)
                if n > 0 { accumulated.append(buf, count: n) }
            }
            buf.deallocate()
            stream.close()
            data = accumulated
        } else {
            return [:]
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
