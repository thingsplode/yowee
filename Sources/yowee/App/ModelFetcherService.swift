import Foundation
import YoweeCore

/// Fetches available model IDs for a given LLM provider.
/// Centralises the Keychain read and client instantiation that were previously in StepEditorView,
/// keeping the view layer free of LLM client details.
///
/// Results are cached for 60 seconds per provider. The cache is invalidated automatically
/// when the provider's credentials change (API key or base URL write triggers invalidation
/// via `invalidate(for:)`). This avoids redundant network calls when navigating between steps.
@MainActor
final class ModelFetcherService {
    static let shared = ModelFetcherService()
    private init() {}

    private struct CacheEntry {
        let models: [String]
        let fetchedAt: Date
    }

    private var cache: [LLMProvider: CacheEntry] = [:]
    private static let ttl: TimeInterval = 60

    // MARK: - Public API

    /// Returns the available model IDs for `provider`, or an empty array if credentials are
    /// missing or the fetch fails. Callers should fall back to `provider.defaultModels`.
    func fetchModels(for provider: LLMProvider) async throws -> [String] {
        if let entry = cache[provider], Date().timeIntervalSince(entry.fetchedAt) < Self.ttl {
            return entry.models
        }
        let models = try await fetchLive(for: provider)
        cache[provider] = CacheEntry(models: models, fetchedAt: Date())
        return models
    }

    /// Removes the cached result for `provider` — call after saving a new API key or base URL.
    func invalidate(for provider: LLMProvider) {
        cache.removeValue(forKey: provider)
    }

    // MARK: - Private

    private func fetchLive(for provider: LLMProvider) async throws -> [String] {
        switch provider {
        case .openai:
            guard let key = KeychainStore.load(for: provider.keychainKey), !key.isEmpty else {
                return []
            }
            let baseURL = UserDefaults.standard.string(forKey: "yowee.openai.baseURL")
                ?? "https://api.openai.com"
            return try await OpenAIClient(apiKey: key, baseURL: baseURL).fetchModels()
        case .ollama:
            let baseURL = UserDefaults.standard.string(forKey: "yowee.ollama.baseURL")
                ?? "http://localhost:11434"
            return try await OllamaClient(baseURL: baseURL).fetchModels()
        case .anthropic:
            return []
        }
    }
}
