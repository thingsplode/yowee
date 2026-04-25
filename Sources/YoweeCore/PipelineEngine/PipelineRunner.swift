import Foundation

/// Controls how many times a failing step is retried and how long to wait between attempts.
public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let delay: Duration

    /// No retries — each step is attempted exactly once.
    public static let none = RetryPolicy(maxAttempts: 1, delay: .seconds(0))
    /// Up to 3 attempts with a 1-second pause between each, applied only to transient errors.
    public static let `default` = RetryPolicy(maxAttempts: 3, delay: .seconds(1))

    public init(maxAttempts: Int, delay: Duration) {
        self.maxAttempts = maxAttempts
        self.delay = delay
    }
}

public actor PipelineRunner {
    private let clientFactory: @Sendable (StepData) -> any LLMClient
    private let retryPolicy: RetryPolicy
    private let log: @Sendable (String) -> Void

    public init(
        clientFactory: @escaping @Sendable (StepData) -> any LLMClient = { LLMClientFactory.client(for: $0, credentials: .load()) },
        retryPolicy: RetryPolicy = .default,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.clientFactory = clientFactory
        self.retryPolicy = retryPolicy
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
            current = try await attempt(client: client, step: step, rendered: rendered, label: label)
            log("step '\(label)' done in \(Int(-start.timeIntervalSinceNow))s")
        }
        return current
    }

    private func attempt(
        client: any LLMClient,
        step: StepData,
        rendered: String,
        label: String
    ) async throws -> String {
        let maxAttempts = max(1, retryPolicy.maxAttempts)
        for attempt in 1...maxAttempts {
            do {
                return try await client.complete(
                    system: step.systemPrompt,
                    user: rendered,
                    model: step.modelID,
                    maxTokens: 4096
                )
            } catch let e as LLMError where e.isTransient && attempt < maxAttempts {
                log("step '\(label)' transient failure (attempt \(attempt)/\(maxAttempts)), retrying")
                try await Task.sleep(for: retryPolicy.delay)
            } catch {
                log("step '\(label)' failed: \(error)")
                throw error
            }
        }
        // Reached only when maxAttempts == 0; guarded by max(1, ...) above.
        throw LLMError.emptyResponse
    }
}
