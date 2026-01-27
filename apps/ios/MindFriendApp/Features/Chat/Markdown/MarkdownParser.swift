import Foundation

/// Represents a parsed element from markdown content
enum MarkdownElement: Equatable {
    case text(String)
    case codeBlock(language: String?, code: String)
    case inlineCode(String)
}

/// Parses markdown content into structured elements for rendering
struct MarkdownParser {

    // Regex pattern for inline code: `code`
    private static let inlineCodePattern = #"`([^`\n]+)`"#

    /// Parse markdown content into an array of elements
    /// Uses a simple split-based approach for reliability
    static func parse(_ content: String) -> [MarkdownElement] {
        // Split content by ``` markers
        let parts = content.components(separatedBy: "```")

        #if DEBUG
        print("[MarkdownParser] Split into \(parts.count) parts")
        #endif

        // If no code blocks found (only 1 part), just parse for inline code
        if parts.count == 1 {
            return parseInlineCode(content)
        }

        var elements: [MarkdownElement] = []
        var isCodeBlock = false

        for (index, part) in parts.enumerated() {
            if isCodeBlock {
                // This part is inside a code block
                // First line is the language identifier, rest is code
                let lines = part.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)

                let language: String?
                let code: String

                if lines.count >= 2 {
                    // Has language identifier on first line
                    let langStr = String(lines[0]).trimmingCharacters(in: .whitespaces)
                    language = langStr.isEmpty ? nil : langStr
                    code = String(lines[1])
                } else if lines.count == 1 {
                    // Just code, no separate language line (or language with no code after)
                    let firstLine = String(lines[0]).trimmingCharacters(in: .whitespaces)
                    // Check if first line looks like a language identifier (single word, no spaces)
                    if firstLine.contains(" ") || firstLine.contains("<") || firstLine.contains("{") {
                        // Looks like code, not a language
                        language = nil
                        code = String(lines[0])
                    } else {
                        // Looks like a language identifier with no code
                        language = firstLine.isEmpty ? nil : firstLine
                        code = ""
                    }
                } else {
                    language = nil
                    code = ""
                }

                // Trim trailing newline from code
                var trimmedCode = code
                while trimmedCode.hasSuffix("\n") || trimmedCode.hasSuffix("\r") {
                    trimmedCode.removeLast()
                }

                #if DEBUG
                print("[MarkdownParser] Code block \(index): language=\(language ?? "nil"), code length=\(trimmedCode.count)")
                #endif

                elements.append(.codeBlock(language: language, code: trimmedCode))
            } else {
                // This part is regular text
                if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let textElements = parseInlineCode(part)
                    elements.append(contentsOf: textElements)
                }
            }

            isCodeBlock.toggle()
        }

        // If no elements were added, return the content as plain text
        if elements.isEmpty {
            return [.text(content)]
        }

        return elements
    }

    /// Parse inline code from text content
    private static func parseInlineCode(_ content: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []

        guard let regex = try? NSRegularExpression(pattern: inlineCodePattern, options: []) else {
            return content.isEmpty ? [] : [.text(content)]
        }

        let nsRange = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: nsRange)

        if matches.isEmpty {
            return content.isEmpty ? [] : [.text(content)]
        }

        var currentIndex = content.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: content),
                  let codeRange = Range(match.range(at: 1), in: content) else {
                continue
            }

            // Add text before inline code
            if currentIndex < fullRange.lowerBound {
                let text = String(content[currentIndex..<fullRange.lowerBound])
                if !text.isEmpty {
                    elements.append(.text(text))
                }
            }

            // Add inline code
            let code = String(content[codeRange])
            elements.append(.inlineCode(code))

            currentIndex = fullRange.upperBound
        }

        // Add remaining text
        if currentIndex < content.endIndex {
            let text = String(content[currentIndex...])
            if !text.isEmpty {
                elements.append(.text(text))
            }
        }

        return elements
    }

    /// Check if a code block contains HTML
    static func isHTMLCodeBlock(language: String?) -> Bool {
        guard let lang = language?.lowercased() else { return false }
        return lang == "html" || lang == "htm"
    }
}
