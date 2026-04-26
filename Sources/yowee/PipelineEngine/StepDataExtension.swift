import YoweeCore

extension StepData {
    init(from step: PromptStep, credentials: Credentials = .load()) {
        var options: [String: Bool] = [:]
        if step.ollamaThinkingDisabled { options["thinkingDisabled"] = true }
        self.init(
            stepKind: step.stepKind,
            systemPrompt: step.systemPrompt,
            userTemplate: step.userTemplate,
            provider: step.provider,
            modelID: step.modelID,
            providerOptions: options,
            queryTemplate: step.queryTemplate,
            tavilyKey: credentials.tavilyKey,
            tavilyMaxResults: step.tavilyMaxResults,
            tavilySearchDepth: step.tavilySearchDepth
        )
    }
}
