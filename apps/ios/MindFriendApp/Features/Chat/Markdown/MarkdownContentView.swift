import SwiftUI

/// Renders markdown content with support for code blocks, inline code, and standard markdown formatting
struct MarkdownContentView: View {
    let content: String
    let isUserMessage: Bool

    @State private var htmlToPreview: String?

    init(content: String, isUserMessage: Bool = false) {
        self.content = content
        self.isUserMessage = isUserMessage
    }

    private var elements: [MarkdownElement] {
        MarkdownParser.parse(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                renderElement(element)
            }
        }
        .sheet(item: $htmlToPreview) { html in
            HTMLPreviewSheet(htmlContent: html)
        }
    }

    // Check raw content for code blocks (fallback-safe even if parser fails)
    private var hasCodeBlocks: Bool {
        content.contains("```")
    }

    @ViewBuilder
    private func renderElement(_ element: MarkdownElement) -> some View {
        switch element {
        case .text(let text):
            // Always apply bubble styling to text elements
            renderMarkdownText(text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isUserMessage ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
                .foregroundStyle(isUserMessage ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: hasCodeBlocks ? 16 : 20))

        case .codeBlock(let language, let code):
            CodeBlockView(code: code, language: language) { html in
                htmlToPreview = html
            }

        case .inlineCode(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isUserMessage ? Color.white.opacity(0.2) : Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder
    private func renderMarkdownText(_ text: String) -> some View {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(text)
                .textSelection(.enabled)
        }
    }
}

// Make String identifiable for sheet presentation
extension String: @retroactive Identifiable {
    public var id: String { self }
}

#Preview("Code Block") {
    MarkdownContentView(content: """
    Here's some Swift code:

    ```swift
    func hello() {
        print("Hello, World!")
    }
    ```

    And some inline `code` here.
    """)
    .padding()
}

#Preview("HTML Preview") {
    MarkdownContentView(content: """
    Here's an HTML example:

    ```html
    <div style="color: blue; padding: 20px;">
        <h1>Hello!</h1>
        <p>This is a paragraph.</p>
    </div>
    ```

    Click Preview to see it rendered.
    """)
    .padding()
}

#Preview("Mixed Content") {
    MarkdownContentView(content: """
    # Heading

    This is **bold** and *italic* text.

    - Item 1
    - Item 2

    Here's some `inline code` in a sentence.

    ```python
    def greet(name):
        return f"Hello, {name}!"
    ```

    And a [link](https://example.com).
    """)
    .padding()
}
