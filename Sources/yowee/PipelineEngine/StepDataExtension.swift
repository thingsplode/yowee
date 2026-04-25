import YoweeCore

extension StepData {
    init(from step: PromptStep) {
        var options: [String: Bool] = [:]
        if step.ollamaThinkingDisabled { options["thinkingDisabled"] = true }
        self.init(
            systemPrompt: step.systemPrompt,
            userTemplate: step.userTemplate,
            provider: step.provider,
            modelID: step.modelID,
            providerOptions: options
        )
    }
}
