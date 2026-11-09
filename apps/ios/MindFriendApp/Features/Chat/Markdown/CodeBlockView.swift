import SwiftUI
import UIKit

/// Renders a fenced code block with syntax highlighting, copy button, and optional HTML preview
struct CodeBlockView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let code: String
    let language: String?
    let onPreviewHTML: ((String) -> Void)?

    @State private var copied = false

    init(code: String, language: String?, onPreviewHTML: ((String) -> Void)? = nil) {
        self.code = code
        self.language = language
        self.onPreviewHTML = onPreviewHTML
    }

    private var isHTML: Bool {
        MarkdownParser.isHTMLCodeBlock(language: language)
    }

    private var displayLanguage: String {
        guard let lang = language?.lowercased() else { return "" }
        switch lang {
        case "js": return "JavaScript"
        case "ts": return "TypeScript"
        case "py": return "Python"
        case "swift": return "Swift"
        case "html", "htm": return "HTML"
        case "css": return "CSS"
        case "json": return "JSON"
        case "javascript": return "JavaScript"
        case "typescript": return "TypeScript"
        case "python": return "Python"
        default: return lang.capitalized
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language label and buttons
            HStack {
                if !displayLanguage.isEmpty {
                    Text(displayLanguage)
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }

                Spacer()

                if isHTML, let onPreview = onPreviewHTML {
                    Button {
                        onPreview(code)
                    } label: {
                        HStack(spacing: SupportTheme.Spacing.xxs) {
                            Image(systemName: "play.fill")
                                .font(.caption2)
                            Text("Preview")
                                .font(.caption)
                        }
                        .foregroundColor(SupportTheme.accent)
                        .frame(minHeight: SupportTheme.minimumTarget)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    copyToClipboard()
                } label: {
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                        Text(copied ? "Copied" : "Copy")
                            .font(.caption)
                    }
                    .foregroundColor(copied ? SupportTheme.accent : SupportTheme.textSecondary)
                    .frame(minHeight: SupportTheme.minimumTarget)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, SupportTheme.Spacing.s)
            .padding(.vertical, SupportTheme.Spacing.xs)
            .background(SupportTheme.surface)

            // Code content with syntax highlighting
            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(SupportTheme.Spacing.s)
            }
            .background(SupportTheme.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                .stroke(SupportTheme.border, lineWidth: 1)
        )
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = code
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            copied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                copied = false
            }
        }
    }
}

#Preview {
    VStack(spacing: SupportTheme.Spacing.m) {
        CodeBlockView(
            code: """
            func greet(name: String) -> String {
                return "Hello, \\(name)!"
            }
            """,
            language: "swift"
        )

        CodeBlockView(
            code: """
            <div class="container">
                <h1>Hello World</h1>
                <p>This is a paragraph.</p>
            </div>
            """,
            language: "html",
            onPreviewHTML: { _ in }
        )

        CodeBlockView(
            code: "const x = 42;",
            language: nil
        )
    }
    .padding()
}
