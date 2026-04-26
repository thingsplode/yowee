import Foundation
import YoweeCore

@Observable
final class PromptStep: Identifiable {
    var id: UUID
    var name: String
    var sortOrder: Int
    var stepKind: StepKind
    // Prompt step fields
    var systemPrompt: String?
    var userTemplate: String
    var providerRaw: String
    var modelID: String
    var ollamaThinkingDisabled: Bool
    // Research step fields
    var queryTemplate: String
    var tavilyMaxResults: Int
    var tavilySearchDepth: String

    var provider: LLMProvider {
        get { LLMProvider(rawValue: providerRaw) ?? .anthropic }
        set { providerRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        userTemplate: String = "{{input}}",
        systemPrompt: String? = nil,
        provider: LLMProvider = .anthropic,
        modelID: String = "claude-sonnet-4-6",
        sortOrder: Int = 0,
        ollamaThinkingDisabled: Bool = false,
        stepKind: StepKind = .prompt,
        queryTemplate: String = "{{input}}",
        tavilyMaxResults: Int = 5,
        tavilySearchDepth: String = "basic"
    ) {
        self.id = id
        self.name = name
        self.userTemplate = userTemplate
        self.systemPrompt = systemPrompt
        providerRaw = provider.rawValue
        self.modelID = modelID
        self.sortOrder = sortOrder
        self.ollamaThinkingDisabled = ollamaThinkingDisabled
        self.stepKind = stepKind
        self.queryTemplate = queryTemplate
        self.tavilyMaxResults = tavilyMaxResults
        self.tavilySearchDepth = tavilySearchDepth
    }
}

extension PromptStep: Hashable {
    static func == (lhs: PromptStep, rhs: PromptStep) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
