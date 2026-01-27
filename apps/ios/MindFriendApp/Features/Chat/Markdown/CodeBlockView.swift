import SwiftUI
import UIKit

/// Renders a fenced code block with syntax highlighting, copy button, and optional HTML preview
struct CodeBlockView: View {
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
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isHTML, let onPreview = onPreviewHTML {
                    Button {
                        onPreview(code)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.caption2)
                            Text("Preview")
                                .font(.caption)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    copyToClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                        Text(copied ? "Copied" : "Copy")
                            .font(.caption)
                    }
                    .foregroundColor(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))

            // Code content with syntax highlighting
            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(Color(.systemGray6))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.systemGray4), lineWidth: 0.5)
        )
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = code
        withAnimation(.easeInOut(duration: 0.2)) {
            copied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copied = false
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
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
