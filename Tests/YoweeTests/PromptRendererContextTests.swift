import Testing
@testable import YoweeCore

@Suite("PromptRenderer — context injection")
struct PromptRendererContextTests {

    @Test func contextReplacedWhenProvided() throws {
        let result = try PromptRenderer.render(
            template: "Background: {{context}}\nTask: {{input}}",
            input: "summarise",
            context: "Some markdown content"
        )
        #expect(result == "Background: Some markdown content\nTask: summarise")
    }

    @Test func contextReplacedWithEmptyStringWhenNil() throws {
        let result = try PromptRenderer.render(
            template: "{{context}}{{input}}",
            input: "hello",
            context: nil
        )
        #expect(result == "hello")
    }

    @Test func contextAndInputReplacedIndependently() throws {
        let result = try PromptRenderer.render(
            template: "CTX={{context}} IN={{input}}",
            input: "abc",
            context: "xyz"
        )
        #expect(result == "CTX=xyz IN=abc")
    }

    @Test func multipleContextPlaceholdersAllReplaced() throws {
        let result = try PromptRenderer.render(
            template: "{{context}} and {{context}}",
            input: "x",
            context: "doc"
        )
        #expect(result == "doc and doc")
    }

    @Test func templateWithoutContextPlaceholderIsNotAnError() throws {
        // context provided but template has no {{context}} — silently ignored
        let result = try PromptRenderer.render(
            template: "Only input: {{input}}",
            input: "hi",
            context: "ignored"
        )
        #expect(result == "Only input: hi")
    }

    @Test func contextDoesNotTriggerSecondPassOnInput() throws {
        // If context content contains {{input}}, it must not be re-substituted.
        let result = try PromptRenderer.render(
            template: "{{context}} {{input}}",
            input: "real",
            context: "{{input}}"
        )
        #expect(result == "{{input}} real")
    }

    @Test func emptyContextReplacesPlaceholderWithEmptyString() throws {
        let result = try PromptRenderer.render(
            template: "before{{context}}after",
            input: "x",
            context: ""
        )
        #expect(result == "beforeafter")
    }

    @Test func unicodeInContextHandledCorrectly() throws {
        let result = try PromptRenderer.render(
            template: "{{context}} — {{input}}",
            input: "task",
            context: "Héllo 🌍"
        )
        #expect(result == "Héllo 🌍 — task")
    }
}
