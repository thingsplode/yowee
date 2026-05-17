import Foundation

public enum PromptRendererError: Error, LocalizedError {
    case missingPlaceholder

    public var errorDescription: String? {
        "Prompt template must contain {{input}} placeholder"
    }
}

public enum PromptRenderer {
    /// Renders a prompt template by substituting `{{input}}` and optionally `{{context}}`.
    ///
    /// Substitution is single-pass: if `context` content itself contains `{{input}}`, that
    /// inner occurrence is NOT re-substituted. This prevents accidental double-expansion.
    ///
    /// - Parameters:
    ///   - template: The prompt template string. Must contain `{{input}}`.
    ///   - input:    The text to inject at every `{{input}}` occurrence.
    ///   - context:  Optional content injected at every `{{context}}` occurrence.
    ///               `nil` or absent → `{{context}}` is replaced with an empty string.
    public static func render(template: String, input: String, context: String? = nil) throws -> String {
        guard template.contains("{{input}}") else { throw PromptRendererError.missingPlaceholder }

        // Use a sentinel to protect context content from {{input}} re-substitution.
        // The sentinel is a private-use Unicode sequence that cannot appear in normal text.
        let contextSentinel = "\u{E000}CTX_CONTENT\u{E001}"

        var result = template
        // Replace {{context}} with sentinel first.
        result = result.replacingOccurrences(of: "{{context}}", with: contextSentinel)
        // Replace {{input}} — any {{input}} inside the original context content is now
        // protected behind the sentinel and will NOT be matched here.
        result = result.replacingOccurrences(of: "{{input}}", with: input)
        // Swap sentinel for the actual context content (or empty string).
        result = result.replacingOccurrences(of: contextSentinel, with: context ?? "")

        return result
    }
}
