import Testing
@testable import YoweeCore

struct PromptRendererTests {
    @Test func renderReplacesPlaceholder() throws {
        let result = try PromptRenderer.render(template: "Fix this: {{input}}", input: "hello world")
        #expect(result == "Fix this: hello world")
    }

    @Test func renderReplacesMultiplePlaceholders() throws {
        let result = try PromptRenderer.render(template: "{{input}} is {{input}}", input: "great")
        #expect(result == "great is great")
    }

    @Test func renderThrowsWhenPlaceholderMissing() {
        #expect(throws: PromptRendererError.missingPlaceholder) {
            try PromptRenderer.render(template: "No placeholder here", input: "anything")
        }
    }

    @Test func renderPreservesWhitespaceInInput() throws {
        let input = "  spaced  \n  text  "
        let result = try PromptRenderer.render(template: "{{input}}", input: input)
        #expect(result == input)
    }
}
