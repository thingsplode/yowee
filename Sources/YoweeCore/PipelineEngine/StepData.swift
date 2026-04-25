import Foundation

// Value-type snapshot of a PromptStep for safe cross-actor passing.
// The init(from:PromptStep) is in the yowee target to avoid importing SwiftData here.
public struct StepData: Sendable {
    public let systemPrompt: String?
    public let userTemplate: String
    public let provider: LLMProvider
    public let modelID: String
    public let ollamaThinkingDisabled: Bool

    public init(
        systemPrompt: String?,
        userTemplate: String,
        provider: LLMProvider,
        modelID: String,
        ollamaThinkingDisabled: Bool = false
    ) {
        self.systemPrompt = systemPrompt
        self.userTemplate = userTemplate
        self.provider = provider
        self.modelID = modelID
        self.ollamaThinkingDisabled = ollamaThinkingDisabled
    }
}
