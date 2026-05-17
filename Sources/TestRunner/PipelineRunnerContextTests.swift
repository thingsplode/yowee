import Testing
import Foundation
@testable import YoweeCore

@Suite("PipelineRunner — context injection")
struct PipelineRunnerContextTests {

    // EchoClient returns the user prompt as-is so we can inspect what was rendered.
    private let echo = PipelineRunner(
        clientFactory: { _ in EchoLLMClient() },
        retryPolicy: .none
    )

    @Test func contextContentInjectedIntoPrompt() async throws {
        let step = StepData(
            userTemplate: "CTX={{context}} Q={{input}}",
            contextContent: "# Background\nSome context."
        )
        let result = try await echo.run(steps: [step], input: "hello")
        #expect(result == "CTX=# Background\nSome context. Q=hello")
    }

    @Test func nilContextContentLeavesPlaceholderEmpty() async throws {
        let step = StepData(
            userTemplate: "{{context}}{{input}}",
            contextContent: nil
        )
        let result = try await echo.run(steps: [step], input: "hi")
        #expect(result == "hi")
    }

    @Test func stepWithoutContextPlaceholderIgnoresContent() async throws {
        let step = StepData(
            userTemplate: "{{input}}",
            contextContent: "should be ignored"
        )
        let result = try await echo.run(steps: [step], input: "works")
        #expect(result == "works")
    }

    @Test func contextContentWithInputPlaceholderIsNotReSubstituted() async throws {
        // Context content containing {{input}} must not be double-expanded.
        let step = StepData(
            userTemplate: "{{context}} {{input}}",
            contextContent: "{{input}}"
        )
        let result = try await echo.run(steps: [step], input: "hello")
        #expect(result == "{{input}} hello")
    }

    @Test func contextPropagatedThroughMultiStepPipeline() async throws {
        // Both steps share the same contextContent; each substitution is independent.
        let steps = [
            StepData(userTemplate: "Step1: {{context}} | {{input}}", contextContent: "BG"),
            StepData(userTemplate: "Step2: {{context}} | {{input}}", contextContent: "BG"),
        ]
        let result = try await echo.run(steps: steps, input: "in")
        // Step 1 output becomes Step 2 input
        let step1Out = "Step1: BG | in"
        #expect(result == "Step2: BG | \(step1Out)")
    }
}

// Local echo client — returns the rendered user prompt unchanged.
private struct EchoLLMClient: LLMClient {
    func complete(system: String?, user: String, model: String, maxTokens: Int) async throws -> String {
        user
    }
}
