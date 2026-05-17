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

    @Test func contextDefaultsToNilWhenOmitted() throws {
        let result = try PromptRenderer.render(template: "{{context}}{{input}}", input: "x")
        #expect(result == "x")
    }

    @Test func contextAndInputReplacedIndependently() throws {
        let result = try PromptRenderer.render(
            template: "CTX={{context}} IN={{input}}",
            input: "bar",
            context: "xyz"
        )
        #expect(result == "CTX=xyz IN=bar")
    }

    @Test func multipleContextOccurrences() throws {
        let result = try PromptRenderer.render(
            template: "{{context}} and {{context}} {{input}}",
            input: "go",
            context: "doc"
        )
        #expect(result == "doc and doc go")
    }

    @Test func contextProvidedButTemplateHasNoContextPlaceholder() throws {
        let result = try PromptRenderer.render(
            template: "Just {{input}}",
            input: "text",
            context: "ignored"
        )
        #expect(result == "Just text")
    }

    @Test func contextContentContainingInputPlaceholderIsNotReSubstituted() throws {
        // Context content that itself contains {{input}} must not be double-expanded.
        let result = try PromptRenderer.render(
            template: "{{context}} {{input}}",
            input: "hello",
            context: "{{input}}"
        )
        #expect(result == "{{input}} hello")
    }

    @Test func emptyContextReplacedWithEmptyString() throws {
        let result = try PromptRenderer.render(
            template: "before{{context}}after {{input}}",
            input: "x",
            context: ""
        )
        #expect(result == "beforeafter x")
    }

    @Test func contextWithMultilineContent() throws {
        let content = "Line 1\nLine 2\nLine 3"
        let result = try PromptRenderer.render(
            template: "CTX:\n{{context}}\nINPUT: {{input}}",
            input: "go",
            context: content
        )
        #expect(result == "CTX:\nLine 1\nLine 2\nLine 3\nINPUT: go")
    }

    @Test func missingInputPlaceholderStillThrowsEvenWithContext() {
        #expect(throws: PromptRendererError.self) {
            try PromptRenderer.render(
                template: "Only {{context}} no input",
                input: "x",
                context: "doc"
            )
        }
    }
}
