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
    private let session: URLSession
    private let log: @Sendable (String) -> Void

    public init(
        clientFactory: @escaping @Sendable (StepData)
            -> any LLMClient = { LLMClientFactory.client(for: $0, credentials: .load()) },
        retryPolicy: RetryPolicy = .default,
        session: URLSession = .shared,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.clientFactory = clientFactory
        self.retryPolicy = retryPolicy
        self.session = session
        self.log = log
    }

    public func run(steps: [StepData], input: String) async throws -> String {
        guard !steps.isEmpty else { return input }
        var current = input
        for step in steps {
            switch step.stepKind {
            case .prompt:
                let rendered = try PromptRenderer.render(template: step.userTemplate, input: current)
                let client = clientFactory(step)
                let label = "\(step.provider.rawValue)/\(step.modelID)"
                log("step '\(label)' starting")
                let start = Date()
                current = try await attempt(client: client, step: step, rendered: rendered, label: label)
                log("step '\(label)' done in \(Int(-start.timeIntervalSinceNow))s")
            case .research:
                log("research step starting (query: \(current.prefix(60))…)")
                let start = Date()
                current = try await runResearch(step: step, query: current)
                log("research step done in \(Int(-start.timeIntervalSinceNow))s")
            }
        }
        return current
    }

    private func runResearch(step: StepData, query: String) async throws -> String {
        let renderedQuery = step.queryTemplate.replacingOccurrences(of: "{{input}}", with: query)
        let results = try await TavilyClient(apiKey: step.tavilyKey, session: session)
            .search(query: renderedQuery, maxResults: step.tavilyMaxResults, depth: step.tavilySearchDepth)

        let jina = JinaReader(session: session)
        let pages: [String?] = await withTaskGroup(of: (Int, String?).self) { group in
            for (idx, result) in results.enumerated() {
                group.addTask { await (idx, jina.fetchMarkdown(url: result.url)) }
            }
            var ordered = [String?](repeating: nil, count: results.count)
            for await (idx, page) in group {
                ordered[idx] = page
            }
            return ordered
        }

        return formatResearch(query: renderedQuery, results: results, pages: pages)
    }

    private func formatResearch(query: String, results: [TavilyResult], pages: [String?]) -> String {
        var md = "# Research: \(query)\n\nFound \(results.count) source(s).\n"
        for (idx, result) in results.enumerated() {
            md += "\n---\n\n## \(idx + 1). \(result.title)\n**Source:** \(result.url)\n\n"
            if let page = pages[idx], !page.isEmpty {
                md += page
            } else {
                md += result.content
            }
            md += "\n"
        }
        return md
    }

    private func attempt(
        client: any LLMClient,
        step: StepData,
        rendered: String,
        label: String
    ) async throws -> String {
        let maxAttempts = max(1, retryPolicy.maxAttempts)
        for attempt in 1 ... maxAttempts {
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
