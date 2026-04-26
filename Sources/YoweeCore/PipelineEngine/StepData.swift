import Foundation

public enum StepKind: String, Codable, Sendable {
    case prompt
    case research
}

/// Value-type snapshot of a PromptStep for safe cross-actor passing.
/// The init(from:PromptStep) is in the yowee target to avoid importing SwiftData here.
public struct StepData: Sendable {
    public let stepKind: StepKind
    // Prompt step fields
    public let systemPrompt: String?
    public let userTemplate: String
    public let provider: LLMProvider
    public let modelID: String
    /// Provider-specific boolean flags (e.g. ["thinkingDisabled": true] for Ollama).
    /// Using a dictionary avoids changing the struct signature for every new provider option.
    public let providerOptions: [String: Bool]
    // Research step fields
    public let queryTemplate: String
    public let tavilyKey: String
    public let tavilyMaxResults: Int
    public let tavilySearchDepth: String

    public init(
        stepKind: StepKind = .prompt,
        systemPrompt: String? = nil,
        userTemplate: String = "",
        provider: LLMProvider = .anthropic,
        modelID: String = "",
        providerOptions: [String: Bool] = [:],
        queryTemplate: String = "{{input}}",
        tavilyKey: String = "",
        tavilyMaxResults: Int = 5,
        tavilySearchDepth: String = "basic"
    ) {
        self.stepKind = stepKind
        self.systemPrompt = systemPrompt
        self.userTemplate = userTemplate
        self.provider = provider
        self.modelID = modelID
        self.providerOptions = providerOptions
        self.queryTemplate = queryTemplate
        self.tavilyKey = tavilyKey
        self.tavilyMaxResults = tavilyMaxResults
        self.tavilySearchDepth = tavilySearchDepth
    }
}
