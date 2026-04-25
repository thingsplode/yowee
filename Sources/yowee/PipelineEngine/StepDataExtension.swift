import YoweeCore

extension StepData {
    init(from step: PromptStep) {
        self.init(
            systemPrompt: step.systemPrompt,
            userTemplate: step.userTemplate,
            provider: step.provider,
            modelID: step.modelID,
            ollamaThinkingDisabled: step.ollamaThinkingDisabled
        )
    }
}
