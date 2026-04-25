import Foundation

public enum PromptRendererError: Error, LocalizedError {
    case missingPlaceholder

    public var errorDescription: String? {
        "Prompt template must contain {{input}} placeholder"
    }
}

public enum PromptRenderer {
    public static func render(template: String, input: String) throws -> String {
        guard template.contains("{{input}}") else { throw PromptRendererError.missingPlaceholder }
        return template.replacingOccurrences(of: "{{input}}", with: input)
    }
}
