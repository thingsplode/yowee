import Foundation

public enum LLMProvider: String, CaseIterable, Codable, Sendable {
    case anthropic
    case openai
    case ollama

    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic (Claude)"
        case .openai: "OpenAI (GPT)"
        case .ollama: "Ollama (Local)"
        }
    }

    public var keychainKey: String {
        "yowee.api.key.\(rawValue)"
    }

    public var defaultModels: [String] {
        switch self {
        case .anthropic: ["claude-sonnet-4-6", "claude-opus-4-7", "claude-haiku-4-5-20251001"]
        case .openai: ["gpt-5", "gpt-5-mini", "gpt-5.4", "gpt-4o", "gpt-4o-mini", "o4-mini", "o3", "o3-mini", "o1", "gpt-4-turbo"]
        case .ollama: ["llama3.2", "mistral", "codellama"]
        }
    }

    public var defaultModelID: String {
        defaultModels[0]
    }

    public var requiresAPIKey: Bool {
        self != .ollama
    }
}
