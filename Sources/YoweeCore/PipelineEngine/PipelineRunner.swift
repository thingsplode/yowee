import Foundation

public actor PipelineRunner {
    private let clientFactory: @Sendable (StepData) -> any LLMClient
    private let log: @Sendable (String) -> Void

    public init(
        clientFactory: @escaping @Sendable (StepData) -> any LLMClient = LLMClientFactory.client,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.clientFactory = clientFactory
        self.log = log
    }

    public func run(steps: [StepData], input: String) async throws -> String {
        guard !steps.isEmpty else { return input }
        var current = input
        for step in steps {
            let rendered = try PromptRenderer.render(template: step.userTemplate, input: current)
            let client = clientFactory(step)
            let label = "\(step.provider.rawValue)/\(step.modelID)"
            log("step '\(label)' starting")
            let start = Date()
            do {
                current = try await client.complete(
                    system: step.systemPrompt,
                    user: rendered,
                    model: step.modelID,
                    maxTokens: 4096
                )
                log("step '\(label)' done in \(Int(-start.timeIntervalSinceNow))s")
            } catch {
                log("step '\(label)' failed after \(Int(-start.timeIntervalSinceNow))s: \(error)")
                throw error
            }
        }
        return current
    }
}
