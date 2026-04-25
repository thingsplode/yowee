import Foundation
import YoweeCore

/// Fetches available model IDs for a given LLM provider.
/// Centralises the Keychain read and client instantiation that were previously in StepEditorView,
/// keeping the view layer free of LLM client details.
@MainActor
final class ModelFetcherService {
    static let shared = ModelFetcherService()
    private init() {}

    /// Returns the available model IDs for `provider`, or an empty array if credentials are
    /// missing or the fetch fails. Callers should fall back to `provider.defaultModels`.
    func fetchModels(for provider: LLMProvider) async throws -> [String] {
        switch provider {
        case .openai:
            guard let key = KeychainStore.load(for: provider.keychainKey), !key.isEmpty else {
                return []
            }
            return try await OpenAIClient(apiKey: key).fetchModels()
        case .ollama:
            let baseURL = UserDefaults.standard.string(forKey: "yowee.ollama.baseURL")
                ?? "http://localhost:11434"
            return try await OllamaClient(baseURL: baseURL).fetchModels()
        case .anthropic:
            return []
        }
    }
}
