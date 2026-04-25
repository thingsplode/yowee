import YoweeCore
import Foundation

@Observable
final class PromptStep: Identifiable {
    var id: UUID
    var name: String
    var sortOrder: Int
    var systemPrompt: String?
    var userTemplate: String
    var providerRaw: String
    var modelID: String
    var ollamaThinkingDisabled: Bool

    var provider: LLMProvider {
        get { LLMProvider(rawValue: providerRaw) ?? .anthropic }
        set { providerRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        userTemplate: String,
        systemPrompt: String? = nil,
        provider: LLMProvider = .anthropic,
        modelID: String = "claude-sonnet-4-6",
        sortOrder: Int = 0,
        ollamaThinkingDisabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.userTemplate = userTemplate
        self.systemPrompt = systemPrompt
        self.providerRaw = provider.rawValue
        self.modelID = modelID
        self.sortOrder = sortOrder
        self.ollamaThinkingDisabled = ollamaThinkingDisabled
    }
}

extension PromptStep: Hashable {
    static func == (lhs: PromptStep, rhs: PromptStep) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
