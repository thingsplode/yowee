import Testing
@testable import YoweeCore

// MARK: - Mock LLM clients

struct MockLLMClient: LLMClient {
    let response: String
    func complete(system: String?, user: String, model: String, maxTokens: Int) async throws -> String {
        response
    }
}

struct EchoClient: LLMClient {
    func complete(system: String?, user: String, model: String, maxTokens: Int) async throws -> String {
        "echo:\(user)"
    }
}

struct FailingLLMClient: LLMClient {
    let error: LLMError
    func complete(system: String?, user: String, model: String, maxTokens: Int) async throws -> String {
        throw error
    }
}

// MARK: - Tests

struct PipelineRunnerTests {
    @Test func singleStepReturnsLLMResponse() async throws {
        let runner = PipelineRunner(clientFactory: { _ in MockLLMClient(response: "Fixed text") })
        let result = try await runner.run(steps: [step("Fix: {{input}}")], input: "broken text")
        #expect(result == "Fixed text")
    }

    @Test func multipleStepsChainOutput() async throws {
        // EchoClient returns "echo:<user prompt>", so chaining verifies each step feeds
        // the previous step's output as its input.
        let runner = PipelineRunner(clientFactory: { _ in EchoClient() })
        let result = try await runner.run(
            steps: [step("A:{{input}}"), step("B:{{input}}")],
            input: "x"
        )
        #expect(result == "echo:B:echo:A:x")
    }

    @Test func emptyStepsReturnsInput() async throws {
        let runner = PipelineRunner(clientFactory: { _ in MockLLMClient(response: "never called") })
        let result = try await runner.run(steps: [], input: "original")
        #expect(result == "original")
    }

    @Test func propagatesLLMError() async throws {
        let runner = PipelineRunner(clientFactory: { _ in
            FailingLLMClient(error: .apiError(statusCode: 401, body: "Unauthorized"))
        })
        await #expect(throws: LLMError.self) {
            try await runner.run(steps: [step("{{input}}")], input: "text")
        }
    }

    private func step(_ template: String) -> StepData {
        StepData(systemPrompt: nil, userTemplate: template, provider: .anthropic, modelID: "test-model")
    }
}
