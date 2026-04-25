import Foundation

// Value-type snapshot of a PromptStep for safe cross-actor passing.
// The init(from:PromptStep) is in the yowee target to avoid importing SwiftData here.
public struct StepData: Sendable {
    public let systemPrompt: String?
    public let userTemplate: String
    public let provider: LLMProvider
    public let modelID: String
    /// Provider-specific boolean flags (e.g. ["thinkingDisabled": true] for Ollama).
    /// Using a dictionary avoids changing the struct signature for every new provider option.
    public let providerOptions: [String: Bool]

    public init(
        systemPrompt: String?,
        userTemplate: String,
        provider: LLMProvider,
        modelID: String,
        providerOptions: [String: Bool] = [:]
    ) {
        self.systemPrompt = systemPrompt
        self.userTemplate = userTemplate
        self.provider = provider
        self.modelID = modelID
        self.providerOptions = providerOptions
    }
}
