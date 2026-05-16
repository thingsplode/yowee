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
    /// When true, passes think:false to Ollama — disables chain-of-thought on models that support it.
    public let ollamaThinkingDisabled: Bool
    /// OpenAI reasoning effort: "low", "medium", "high", or "none". nil = API default.
    /// Only sent for o-series models (o1, o3, o4-mini, etc.).
    public let openAIReasoningEffort: String?
    /// Request timeout in seconds. Applies to the LLM completion call; model-fetch calls use their own fixed timeout.
    public let timeoutSeconds: Int
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
        ollamaThinkingDisabled: Bool = false,
        openAIReasoningEffort: String? = nil,
        timeoutSeconds: Int = 60,
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
        self.ollamaThinkingDisabled = ollamaThinkingDisabled
        self.openAIReasoningEffort = openAIReasoningEffort
        self.timeoutSeconds = timeoutSeconds
        self.queryTemplate = queryTemplate
        self.tavilyKey = tavilyKey
        self.tavilyMaxResults = tavilyMaxResults
        self.tavilySearchDepth = tavilySearchDepth
    }
}
