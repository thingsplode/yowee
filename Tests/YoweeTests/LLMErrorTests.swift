import Testing
@testable import YoweeCore

@Suite("LLMError")
struct LLMErrorTests {

    // MARK: apiError descriptions

    @Test func error401MentionsAPIKey() {
        let error = LLMError.apiError(statusCode: 401, body: "Unauthorized")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("401"))
        #expect(desc.lowercased().contains("key") || desc.lowercased().contains("api"))
    }

    @Test func error429MentionsRateLimit() {
        let error = LLMError.apiError(statusCode: 429, body: "Too Many Requests")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("429"))
        #expect(desc.lowercased().contains("rate") || desc.lowercased().contains("limit") || desc.lowercased().contains("wait"))
    }

    @Test func otherAPIErrorIncludesStatusCode() {
        let error = LLMError.apiError(statusCode: 500, body: "Internal Server Error")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("500"))
    }

    @Test func otherAPIErrorIncludesBodyPrefix() {
        let body = "Internal Server Error — detailed message here"
        let error = LLMError.apiError(statusCode: 503, body: body)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("Internal Server Error"))
    }

    @Test func longAPIErrorBodyTruncatedAt120Chars() {
        let longBody = String(repeating: "X", count: 200)
        let error = LLMError.apiError(statusCode: 503, body: longBody)
        let desc = error.errorDescription ?? ""
        // The body prefix is capped at 120 chars — description must not contain 200 Xs
        let xCount = desc.filter { $0 == "X" }.count
        #expect(xCount <= 120)
    }

    // MARK: other cases

    @Test func emptyResponseHasDescription() {
        let desc = LLMError.emptyResponse.errorDescription ?? ""
        #expect(!desc.isEmpty)
    }

    @Test func invalidURLHasDescription() {
        let desc = LLMError.invalidURL.errorDescription ?? ""
        #expect(!desc.isEmpty)
    }

    @Test func timeoutHasDescription() {
        let desc = LLMError.timeout(seconds: 60).errorDescription ?? ""
        #expect(!desc.isEmpty)
        #expect(desc.lowercased().contains("timeout") || desc.lowercased().contains("timed"))
    }

    // MARK: LocalizedError conformance

    @Test func allCasesProvideNonNilDescription() {
        let errors: [LLMError] = [
            .apiError(statusCode: 401, body: ""),
            .apiError(statusCode: 429, body: ""),
            .apiError(statusCode: 500, body: "err"),
            .emptyResponse,
            .invalidURL,
            .timeout(seconds: 60),
        ]
        for error in errors {
            #expect(error.errorDescription != nil, "\(error) should have a description")
        }
    }
}
