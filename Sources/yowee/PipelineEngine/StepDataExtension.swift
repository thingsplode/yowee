import YoweeCore

extension StepData {
    init(from step: PromptStep, credentials: Credentials = .load()) {
        self.init(
            stepKind: step.stepKind,
            systemPrompt: step.systemPrompt,
            userTemplate: step.userTemplate,
            provider: step.provider,
            modelID: step.modelID,
            ollamaThinkingDisabled: step.ollamaThinkingDisabled,
            openAIReasoningEffort: step.openAIReasoningEffort,
            timeoutSeconds: step.timeoutSeconds,
            queryTemplate: step.queryTemplate,
            tavilyKey: credentials.tavilyKey,
            tavilyMaxResults: step.tavilyMaxResults,
            tavilySearchDepth: step.tavilySearchDepth
        )
    }
}
