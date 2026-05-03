import Foundation

public enum LLMClientFactory {
    /// Returns the appropriate LLM client for `step` using the provided `credentials`.
    /// Credentials are passed explicitly so this function is free of global state and easy to test.
    @Sendable
    public static func client(for step: StepData, credentials: Credentials) -> any LLMClient {
        switch step.provider {
        case .anthropic:
            return AnthropicClient(apiKey: credentials.anthropicKey)
        case .openai:
            return OpenAIClient(
                apiKey: credentials.openAIKey,
                baseURL: credentials.openAIBaseURL,
                reasoningEffort: step.openAIReasoningEffort
            )
        case .ollama:
            let thinkingDisabled = step.providerOptions["thinkingDisabled"] ?? false
            return OllamaClient(baseURL: credentials.ollamaBaseURL, thinkingDisabled: thinkingDisabled)
        }
    }
}
