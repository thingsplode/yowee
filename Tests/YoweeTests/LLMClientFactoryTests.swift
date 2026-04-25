import Testing
@testable import YoweeCore

struct LLMClientFactoryTests {
    @Test func anthropicProviderReturnsAnthropicClient() {
        #expect(LLMClientFactory.client(for: step(.anthropic), credentials: .empty) is AnthropicClient)
    }

    @Test func openAIProviderReturnsOpenAIClient() {
        #expect(LLMClientFactory.client(for: step(.openai), credentials: .empty) is OpenAIClient)
    }

    @Test func ollamaProviderReturnsOllamaClient() {
        #expect(LLMClientFactory.client(for: step(.ollama), credentials: .empty) is OllamaClient)
    }

    @Test func allProvidersAreHandled() {
        for provider in LLMProvider.allCases {
            _ = LLMClientFactory.client(for: step(provider), credentials: .empty)
        }
    }

    private func step(_ provider: LLMProvider) -> StepData {
        StepData(systemPrompt: nil, userTemplate: "{{input}}", provider: provider, modelID: "m")
    }
}
