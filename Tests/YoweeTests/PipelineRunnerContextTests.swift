import Testing
import Foundation
@testable import YoweeCore

@Suite("PipelineRunner — context file")
struct PipelineRunnerContextTests {

    // EchoClient returns "echo:<user prompt>" so we can inspect what was rendered.
    private let echo = PipelineRunner(
        clientFactory: { _ in EchoLLMClient() },
        retryPolicy: .none
    )

    @Test func contextFileContentInjectedIntoPrompt() async throws {
        let file = try writeTempFile(content: "# Background\nSome context.")
        defer { try? FileManager.default.removeItem(atPath: file) }

        let step = StepData(
            userTemplate: "CTX={{context}} Q={{input}}",
            contextFilePath: file
        )
        let result = try await echo.run(steps: [step], input: "hello")
        #expect(result == "echo:CTX=# Background\nSome context. Q=hello")
    }

    @Test func missingContextFileThrowsContextFileUnreadable() async throws {
        let step = StepData(
            userTemplate: "{{context}} {{input}}",
            contextFilePath: "/nonexistent/path/file.md"
        )
        await #expect(throws: LLMError.self) {
            try await echo.run(steps: [step], input: "x")
        }
    }

    @Test func nilContextFilePathLeavesContextPlaceholderEmpty() async throws {
        let step = StepData(
            userTemplate: "{{context}}{{input}}",
            contextFilePath: nil
        )
        let result = try await echo.run(steps: [step], input: "hi")
        #expect(result == "echo:hi")
    }

    @Test func stepWithoutContextPlaceholderAndFileSetStillWorks() async throws {
        let file = try writeTempFile(content: "ignored")
        defer { try? FileManager.default.removeItem(atPath: file) }

        let step = StepData(
            userTemplate: "{{input}}",
            contextFilePath: file
        )
        let result = try await echo.run(steps: [step], input: "works")
        #expect(result == "echo:works")
    }

    // MARK: - Helpers

    private func writeTempFile(content: String) throws -> String {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".md"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}

// Local echo client — avoids dependency on PipelineRunnerTests.swift's EchoClient
private struct EchoLLMClient: LLMClient {
    func complete(system: String?, user: String, model: String, maxTokens: Int) async throws -> String {
        "echo:\(user)"
    }
}
