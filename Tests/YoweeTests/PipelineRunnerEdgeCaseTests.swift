import Testing
@testable import YoweeCore

// MARK: - Helpers

private struct RecordingClient: LLMClient {
    actor Recorder {
        private(set) var calls: [(system: String?, user: String, model: String, maxTokens: Int)] = []
        func record(system: String?, user: String, model: String, maxTokens: Int) {
            calls.append((system, user, model, maxTokens))
        }
    }

    let recorder: Recorder
    let response: String

    func complete(system: String?, user: String, model: String, maxTokens: Int) async throws -> String {
        await recorder.record(system: system, user: user, model: model, maxTokens: maxTokens)
        return response
    }
}

private struct FailOnceClient: LLMClient {
    actor State { var called = false }
    let state = State()
    let firstError: LLMError
    let successResponse: String

    func complete(system: String?, user: String, model: String, maxTokens: Int) async throws -> String {
        let alreadyCalled = await state.called
        if !alreadyCalled {
            await state.set()
            throw firstError
        }
        return successResponse
    }
}

extension FailOnceClient.State {
    func set() { called = true }
}

// MARK: - Tests

@Suite("PipelineRunner — edge cases")
struct PipelineRunnerEdgeCaseTests {

    private func makeRunner(response: String = "ok") -> (PipelineRunner, RecordingClient.Recorder) {
        let recorder = RecordingClient.Recorder()
        let runner = PipelineRunner(clientFactory: { _ in RecordingClient(recorder: recorder, response: response) })
        return (runner, recorder)
    }

    // MARK: Template rendering

    @Test func invalidTemplateThrowsBeforeCallingLLM() async throws {
        let (runner, recorder) = makeRunner()
        let step = StepData(systemPrompt: nil, userTemplate: "no placeholder here",
                            provider: .anthropic, modelID: "claude-sonnet-4-6")
        await #expect(throws: (any Error).self) {
            try await runner.run(steps: [step], input: "hello")
        }
        let calls = await recorder.calls
        #expect(calls.isEmpty, "LLM should never be called if template is invalid")
    }

    @Test func templateRenderedCorrectlyBeforeLLMCall() async throws {
        let (runner, recorder) = makeRunner(response: "result")
        let step = StepData(systemPrompt: nil, userTemplate: "Translate: {{input}}",
                            provider: .anthropic, modelID: "m")
        _ = try await runner.run(steps: [step], input: "hello")
        let calls = await recorder.calls
        #expect(calls.first?.user == "Translate: hello")
    }

    // MARK: System prompt

    @Test func systemPromptPassedToLLMClient() async throws {
        let (runner, recorder) = makeRunner(response: "result")
        let step = StepData(systemPrompt: "Be concise", userTemplate: "{{input}}",
                            provider: .anthropic, modelID: "m")
        _ = try await runner.run(steps: [step], input: "hello")
        let calls = await recorder.calls
        #expect(calls.first?.system == "Be concise")
    }

    @Test func nilSystemPromptPassedAsNil() async throws {
        let (runner, recorder) = makeRunner(response: "result")
        let step = StepData(systemPrompt: nil, userTemplate: "{{input}}",
                            provider: .anthropic, modelID: "m")
        _ = try await runner.run(steps: [step], input: "hello")
        let calls = await recorder.calls
        #expect(calls.first?.system == nil)
    }

    // MARK: Model routing

    @Test func modelIDPassedToLLMClient() async throws {
        let (runner, recorder) = makeRunner(response: "result")
        let step = StepData(systemPrompt: nil, userTemplate: "{{input}}",
                            provider: .anthropic, modelID: "claude-opus-4-7")
        _ = try await runner.run(steps: [step], input: "hello")
        let calls = await recorder.calls
        #expect(calls.first?.model == "claude-opus-4-7")
    }

    @Test func maxTokensDefaultIs4096() async throws {
        let (runner, recorder) = makeRunner(response: "result")
        let step = StepData(systemPrompt: nil, userTemplate: "{{input}}",
                            provider: .anthropic, modelID: "m")
        _ = try await runner.run(steps: [step], input: "hello")
        let calls = await recorder.calls
        #expect(calls.first?.maxTokens == 4096)
    }

    // MARK: Multi-step chaining

    @Test func threeStepsChainCorrectly() async throws {
        let echoRunner = PipelineRunner(clientFactory: { _ in EchoStepClient() })
        let steps = [
            StepData(systemPrompt: nil, userTemplate: "A:{{input}}", provider: .anthropic, modelID: "m"),
            StepData(systemPrompt: nil, userTemplate: "B:{{input}}", provider: .anthropic, modelID: "m"),
            StepData(systemPrompt: nil, userTemplate: "C:{{input}}", provider: .anthropic, modelID: "m"),
        ]
        let result = try await echoRunner.run(steps: steps, input: "X")
        #expect(result == "C:B:A:X")
    }

    @Test func secondStepReceivesFirstStepOutput() async throws {
        let echoRunner = PipelineRunner(clientFactory: { _ in EchoStepClient() })
        let steps = [
            StepData(systemPrompt: nil, userTemplate: "first:{{input}}", provider: .anthropic, modelID: "m"),
            StepData(systemPrompt: nil, userTemplate: "second:{{input}}", provider: .anthropic, modelID: "m"),
        ]
        let result = try await echoRunner.run(steps: steps, input: "start")
        #expect(result == "second:first:start")
    }

    // MARK: Error propagation

    @Test func errorInFirstStepPropagates() async throws {
        let runner = PipelineRunner(clientFactory: { _ in
            struct AlwaysFailClient: LLMClient {
                func complete(system: String?, user: String, model: String, maxTokens: Int) async throws -> String {
                    throw LLMError.emptyResponse
                }
            }
            return AlwaysFailClient()
        })
        let steps = [
            StepData(systemPrompt: nil, userTemplate: "{{input}}", provider: .anthropic, modelID: "m"),
            StepData(systemPrompt: nil, userTemplate: "{{input}}", provider: .anthropic, modelID: "m"),
        ]
        await #expect(throws: LLMError.self) {
            try await runner.run(steps: steps, input: "hello")
        }
    }

    @Test func errorInMiddleStepPropagates() async throws {
        // Step 1 succeeds, step 2 fails — the runner routes by step.provider to pick the client.
        let runner = PipelineRunner(clientFactory: { step in
            struct ConditionalFailClient: LLMClient {
                let shouldFail: Bool
                func complete(system: String?, user: String, model: String, maxTokens: Int) async throws -> String {
                    if shouldFail { throw LLMError.timeout }
                    return "ok"
                }
            }
            // anthropic → succeeds, openai → fails
            return ConditionalFailClient(shouldFail: step.provider == .openai)
        })
        let steps = [
            StepData(systemPrompt: nil, userTemplate: "{{input}}", provider: .anthropic, modelID: "m"),
            StepData(systemPrompt: nil, userTemplate: "{{input}}", provider: .openai,    modelID: "m"),
            StepData(systemPrompt: nil, userTemplate: "{{input}}", provider: .anthropic, modelID: "m"),
        ]
        await #expect(throws: LLMError.self) {
            try await runner.run(steps: steps, input: "hello")
        }
    }
}

// Echo client that returns the rendered user prompt as-is (for chaining tests)
private struct EchoStepClient: LLMClient {
    func complete(system: String?, user: String, model: String, maxTokens: Int) async throws -> String {
        user
    }
}
