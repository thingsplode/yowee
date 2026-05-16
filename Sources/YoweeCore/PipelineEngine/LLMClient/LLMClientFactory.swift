import Foundation

public enum LLMClientFactory {
    /// Returns the appropriate LLM client for `step` using the provided `credentials`.
    /// Credentials are passed explicitly so this function is free of global state and easy to test.
    @Sendable
    public static func client(for step: StepData, credentials: Credentials) -> any LLMClient {
        switch step.provider {
        case .anthropic:
            return AnthropicClient(apiKey: credentials.anthropicKey, timeout: TimeInterval(step.timeoutSeconds))
        case .openai:
            return OpenAIClient(
                apiKey: credentials.openAIKey,
                baseURL: credentials.openAIBaseURL,
                reasoningEffort: step.openAIReasoningEffort,
                timeout: TimeInterval(step.timeoutSeconds)
            )
        case .ollama:
            return OllamaClient(
                baseURL: credentials.ollamaBaseURL,
                thinkingDisabled: step.ollamaThinkingDisabled,
                timeout: TimeInterval(step.timeoutSeconds)
            )
        }
    }
}
