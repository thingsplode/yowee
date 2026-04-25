import Foundation

/// Snapshot of all provider credentials and base URLs, loaded once at pipeline-run time.
/// Passing credentials explicitly keeps `LLMClientFactory` free of global state reads,
/// making it straightforward to test with arbitrary key/URL values.
public struct Credentials: Sendable {
    public let anthropicKey: String
    public let openAIKey: String
    public let openAIBaseURL: String
    public let ollamaBaseURL: String

    public init(
        anthropicKey: String,
        openAIKey: String,
        openAIBaseURL: String = "https://api.openai.com",
        ollamaBaseURL: String = "http://localhost:11434"
    ) {
        self.anthropicKey = anthropicKey
        self.openAIKey = openAIKey
        self.openAIBaseURL = openAIBaseURL
        self.ollamaBaseURL = ollamaBaseURL
    }

    /// Loads live credentials from Keychain and UserDefaults.
    public static func load() -> Credentials {
        Credentials(
            anthropicKey: KeychainStore.load(for: LLMProvider.anthropic.keychainKey) ?? "",
            openAIKey: KeychainStore.load(for: LLMProvider.openai.keychainKey) ?? "",
            openAIBaseURL: UserDefaults.standard.string(forKey: "yowee.openai.baseURL") ?? "https://api.openai.com",
            ollamaBaseURL: UserDefaults.standard.string(forKey: "yowee.ollama.baseURL") ?? "http://localhost:11434"
        )
    }

    /// Empty credentials — useful in unit tests that verify client routing, not actual API calls.
    public static let empty = Credentials(anthropicKey: "", openAIKey: "")
}
