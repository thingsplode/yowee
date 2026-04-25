import Testing
@testable import YoweeCore

@Suite("LLMProvider")
struct LLMProviderTests {

    // MARK: displayName

    @Test func anthropicDisplayName() {
        #expect(LLMProvider.anthropic.displayName == "Anthropic (Claude)")
    }

    @Test func openAIDisplayName() {
        #expect(LLMProvider.openai.displayName == "OpenAI (GPT)")
    }

    @Test func ollamaDisplayName() {
        #expect(LLMProvider.ollama.displayName == "Ollama (Local)")
    }

    @Test func allProvidersHaveNonEmptyDisplayName() {
        for provider in LLMProvider.allCases {
            #expect(!provider.displayName.isEmpty)
        }
    }

    // MARK: keychainKey

    @Test func keychainKeyContainsRawValue() {
        for provider in LLMProvider.allCases {
            #expect(provider.keychainKey.contains(provider.rawValue))
        }
    }

    @Test func keychainKeysAreUnique() {
        let keys = LLMProvider.allCases.map(\.keychainKey)
        #expect(Set(keys).count == keys.count)
    }

    // MARK: defaultModels

    @Test func anthropicDefaultModelsNonEmpty() {
        #expect(!LLMProvider.anthropic.defaultModels.isEmpty)
    }

    @Test func openAIDefaultModelsNonEmpty() {
        #expect(!LLMProvider.openai.defaultModels.isEmpty)
    }

    @Test func openAIDefaultModelsIncludesGPT5() {
        #expect(LLMProvider.openai.defaultModels.contains("gpt-5"))
    }

    @Test func openAIDefaultModelsIncludesGPT4o() {
        #expect(LLMProvider.openai.defaultModels.contains("gpt-4o"))
    }

    @Test func openAIDefaultModelsIncludesO3() {
        #expect(LLMProvider.openai.defaultModels.contains("o3"))
    }

    @Test func defaultModelIDIsFirstModel() {
        for provider in LLMProvider.allCases {
            #expect(provider.defaultModelID == provider.defaultModels[0])
        }
    }

    @Test func openAIDefaultModelIDIsGPT5() {
        #expect(LLMProvider.openai.defaultModelID == "gpt-5")
    }

    @Test func ollamaDefaultModelsNonEmpty() {
        #expect(!LLMProvider.ollama.defaultModels.isEmpty)
    }

    @Test func allDefaultModelsAreNonEmptyStrings() {
        for provider in LLMProvider.allCases {
            for model in provider.defaultModels {
                #expect(!model.isEmpty, "Model ID should not be empty for \(provider)")
            }
        }
    }

    // MARK: requiresAPIKey

    @Test func anthropicRequiresAPIKey() {
        #expect(LLMProvider.anthropic.requiresAPIKey)
    }

    @Test func openAIRequiresAPIKey() {
        #expect(LLMProvider.openai.requiresAPIKey)
    }

    @Test func ollamaDoesNotRequireAPIKey() {
        #expect(!LLMProvider.ollama.requiresAPIKey)
    }

    // MARK: CaseIterable / RawRepresentable

    @Test func threeProvidersExist() {
        #expect(LLMProvider.allCases.count == 3)
    }

    @Test func rawValueRoundTrip() {
        for provider in LLMProvider.allCases {
            let reconstructed = LLMProvider(rawValue: provider.rawValue)
            #expect(reconstructed == provider)
        }
    }

    @Test func unknownRawValueReturnsNil() {
        #expect(LLMProvider(rawValue: "unknown_provider") == nil)
    }
}
