import Foundation

public enum LLMClientFactory {
    @Sendable
    public static func client(for step: StepData) -> any LLMClient {
        switch step.provider {
        case .anthropic:
            let key = KeychainStore.load(for: step.provider.keychainKey) ?? ""
            return AnthropicClient(apiKey: key)
        case .openai:
            let key = KeychainStore.load(for: step.provider.keychainKey) ?? ""
            let baseURL = UserDefaults.standard.string(forKey: "yowee.openai.baseURL") ?? "https://api.openai.com"
            return OpenAIClient(apiKey: key, baseURL: baseURL)
        case .ollama:
            let baseURL = UserDefaults.standard.string(forKey: "yowee.ollama.baseURL") ?? "http://localhost:11434"
            return OllamaClient(baseURL: baseURL, thinkingDisabled: step.ollamaThinkingDisabled)
        }
    }
}
