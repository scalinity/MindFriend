import SwiftUI

/// Provides syntax highlighting for code blocks
struct SyntaxHighlighter {

    /// Color theme for syntax highlighting
    struct Theme {
        let keyword: Color
        let string: Color
        let comment: Color
        let number: Color
        let type: Color
        let function: Color
        let property: Color
        let tag: Color
        let attribute: Color
        let plain: Color

        static var `default`: Theme {
            Theme(
                keyword: Color(red: 0.78, green: 0.42, blue: 0.84),   // Purple
                string: Color(red: 0.87, green: 0.44, blue: 0.36),   // Salmon
                comment: Color(red: 0.45, green: 0.50, blue: 0.55),  // Gray
                number: Color(red: 0.82, green: 0.68, blue: 0.40),   // Gold
                type: Color(red: 0.35, green: 0.75, blue: 0.85),     // Cyan
                function: Color(red: 0.40, green: 0.72, blue: 0.42), // Green
                property: Color(red: 0.70, green: 0.80, blue: 0.90), // Light blue
                tag: Color(red: 0.90, green: 0.45, blue: 0.45),      // Red
                attribute: Color(red: 0.80, green: 0.70, blue: 0.45), // Yellow-orange
                plain: Color.primary
            )
        }
    }

    /// Highlight code with the given language
    static func highlight(_ code: String, language: String?, theme: Theme = .default) -> AttributedString {
        guard let language = language?.lowercased() else {
            return AttributedString(code)
        }

        switch language {
        case "swift":
            return highlightSwift(code, theme: theme)
        case "javascript", "js":
            return highlightJavaScript(code, theme: theme)
        case "typescript", "ts":
            return highlightTypeScript(code, theme: theme)
        case "python", "py":
            return highlightPython(code, theme: theme)
        case "html", "htm":
            return highlightHTML(code, theme: theme)
        case "css":
            return highlightCSS(code, theme: theme)
        case "json":
            return highlightJSON(code, theme: theme)
        default:
            return AttributedString(code)
        }
    }

    // MARK: - Language-specific highlighters

    private static func highlightSwift(_ code: String, theme: Theme) -> AttributedString {
        let keywords = ["func", "var", "let", "if", "else", "for", "while", "return", "import", "struct", "class", "enum", "protocol", "extension", "guard", "switch", "case", "default", "break", "continue", "throw", "throws", "try", "catch", "async", "await", "private", "public", "internal", "fileprivate", "open", "static", "final", "override", "init", "deinit", "self", "super", "nil", "true", "false", "some", "any", "where", "in", "is", "as", "typealias", "associatedtype", "mutating", "nonmutating", "lazy", "weak", "unowned", "inout", "defer", "do", "repeat", "fallthrough"]
        let types = ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Optional", "Result", "Error", "Void", "Any", "AnyObject", "Self", "Type", "Never"]

        return applyHighlighting(code, keywords: keywords, types: types, theme: theme, commentPrefix: "//", multilineCommentStart: "/*", multilineCommentEnd: "*/")
    }

    private static func highlightJavaScript(_ code: String, theme: Theme) -> AttributedString {
        let keywords = ["function", "var", "let", "const", "if", "else", "for", "while", "return", "import", "export", "default", "class", "extends", "constructor", "new", "this", "super", "null", "undefined", "true", "false", "try", "catch", "finally", "throw", "async", "await", "typeof", "instanceof", "in", "of", "switch", "case", "break", "continue", "delete", "void", "yield", "static", "get", "set", "from", "as"]
        let types = ["Array", "Object", "String", "Number", "Boolean", "Function", "Symbol", "Map", "Set", "Promise", "Date", "RegExp", "Error", "JSON", "Math", "console"]

        return applyHighlighting(code, keywords: keywords, types: types, theme: theme, commentPrefix: "//", multilineCommentStart: "/*", multilineCommentEnd: "*/")
    }

    private static func highlightTypeScript(_ code: String, theme: Theme) -> AttributedString {
        let keywords = ["function", "var", "let", "const", "if", "else", "for", "while", "return", "import", "export", "default", "class", "extends", "constructor", "new", "this", "super", "null", "undefined", "true", "false", "try", "catch", "finally", "throw", "async", "await", "typeof", "instanceof", "in", "of", "switch", "case", "break", "continue", "delete", "void", "yield", "static", "get", "set", "from", "as", "type", "interface", "enum", "namespace", "module", "declare", "abstract", "implements", "private", "public", "protected", "readonly", "keyof", "infer", "extends", "never", "unknown", "any"]
        let types = ["string", "number", "boolean", "void", "null", "undefined", "never", "unknown", "any", "object", "Array", "Object", "String", "Number", "Boolean", "Function", "Symbol", "Map", "Set", "Promise", "Date", "RegExp", "Error", "Partial", "Required", "Pick", "Omit", "Record", "Exclude", "Extract", "NonNullable", "ReturnType", "Parameters"]

        return applyHighlighting(code, keywords: keywords, types: types, theme: theme, commentPrefix: "//", multilineCommentStart: "/*", multilineCommentEnd: "*/")
    }

    private static func highlightPython(_ code: String, theme: Theme) -> AttributedString {
        let keywords = ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "raise", "with", "pass", "break", "continue", "yield", "lambda", "and", "or", "not", "in", "is", "True", "False", "None", "global", "nonlocal", "assert", "del", "async", "await"]
        let types = ["int", "float", "str", "bool", "list", "dict", "set", "tuple", "bytes", "type", "object", "Exception", "print", "len", "range", "enumerate", "zip", "map", "filter", "sorted", "reversed", "any", "all", "sum", "min", "max", "abs", "round", "open", "input"]

        return applyHighlighting(code, keywords: keywords, types: types, theme: theme, commentPrefix: "#", multilineCommentStart: nil, multilineCommentEnd: nil)
    }

    private static func highlightHTML(_ code: String, theme: Theme) -> AttributedString {
        var result = AttributedString(code)

        // Highlight HTML tags
        let tagPattern = #"<\/?([a-zA-Z][a-zA-Z0-9]*)"#
        if let regex = try? NSRegularExpression(pattern: tagPattern, options: []) {
            let nsRange = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range, in: code),
                      let attributedRange = Range(range, in: result) else { continue }
                result[attributedRange].foregroundColor = theme.tag
            }
        }

        // Highlight attributes
        let attrPattern = #"([a-zA-Z\-]+)="#
        if let regex = try? NSRegularExpression(pattern: attrPattern, options: []) {
            let nsRange = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range(at: 1), in: code),
                      let attributedRange = Range(range, in: result) else { continue }
                result[attributedRange].foregroundColor = theme.attribute
            }
        }

        // Highlight strings (attribute values)
        highlightStrings(in: &result, code: code, theme: theme)

        // Highlight comments
        highlightComments(in: &result, code: code, prefix: nil, multiStart: "<!--", multiEnd: "-->", theme: theme)

        return result
    }

    private static func highlightCSS(_ code: String, theme: Theme) -> AttributedString {
        var result = AttributedString(code)

        // Highlight selectors (before {)
        let selectorPattern = #"([.#]?[a-zA-Z][a-zA-Z0-9_\-]*)\s*\{"#
        if let regex = try? NSRegularExpression(pattern: selectorPattern, options: []) {
            let nsRange = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range(at: 1), in: code),
                      let attributedRange = Range(range, in: result) else { continue }
                result[attributedRange].foregroundColor = theme.type
            }
        }

        // Highlight properties
        let propertyPattern = #"([a-zA-Z\-]+)\s*:"#
        if let regex = try? NSRegularExpression(pattern: propertyPattern, options: []) {
            let nsRange = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range(at: 1), in: code),
                      let attributedRange = Range(range, in: result) else { continue }
                result[attributedRange].foregroundColor = theme.property
            }
        }

        // Highlight strings
        highlightStrings(in: &result, code: code, theme: theme)

        // Highlight numbers with units
        let numberPattern = #"\b(\d+(?:\.\d+)?)(px|em|rem|%|vh|vw|deg|s|ms)?\b"#
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            let nsRange = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range, in: code),
                      let attributedRange = Range(range, in: result) else { continue }
                result[attributedRange].foregroundColor = theme.number
            }
        }

        // Highlight comments
        highlightComments(in: &result, code: code, prefix: nil, multiStart: "/*", multiEnd: "*/", theme: theme)

        return result
    }

    private static func highlightJSON(_ code: String, theme: Theme) -> AttributedString {
        var result = AttributedString(code)

        // Highlight keys
        let keyPattern = #""([^"]+)"\s*:"#
        if let regex = try? NSRegularExpression(pattern: keyPattern, options: []) {
            let nsRange = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range(at: 1), in: code),
                      let attributedRange = Range(range, in: result) else { continue }
                result[attributedRange].foregroundColor = theme.property
            }
        }

        // Highlight string values
        let stringPattern = #":\s*"([^"]*)""#
        if let regex = try? NSRegularExpression(pattern: stringPattern, options: []) {
            let nsRange = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range(at: 1), in: code),
                      let attributedRange = Range(range, in: result) else { continue }
                result[attributedRange].foregroundColor = theme.string
            }
        }

        // Highlight numbers
        let numberPattern = #":\s*(-?\d+(?:\.\d+)?)"#
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            let nsRange = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range(at: 1), in: code),
                      let attributedRange = Range(range, in: result) else { continue }
                result[attributedRange].foregroundColor = theme.number
            }
        }

        // Highlight booleans and null
        let boolPattern = #"\b(true|false|null)\b"#
        if let regex = try? NSRegularExpression(pattern: boolPattern, options: []) {
            let nsRange = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range, in: code),
                      let attributedRange = Range(range, in: result) else { continue }
                result[attributedRange].foregroundColor = theme.keyword
            }
        }

        return result
    }

    // MARK: - Helpers

    private static func applyHighlighting(_ code: String, keywords: [String], types: [String], theme: Theme, commentPrefix: String?, multilineCommentStart: String?, multilineCommentEnd: String?) -> AttributedString {
        var result = AttributedString(code)

        // Highlight keywords
        for keyword in keywords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(code.startIndex..., in: code)
                let matches = regex.matches(in: code, options: [], range: nsRange)

                for match in matches {
                    guard let range = Range(match.range, in: code),
                          let attributedRange = Range(range, in: result) else { continue }
                    result[attributedRange].foregroundColor = theme.keyword
                }
            }
        }

        // Highlight types
        for type in types {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: type))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(code.startIndex..., in: code)
                let matches = regex.matches(in: code, options: [], range: nsRange)

                for match in matches {
                    guard let range = Range(match.range, in: code),
                          let attributedRange = Range(range, in: result) else { continue }
                    result[attributedRange].foregroundColor = theme.type
                }
            }
        }

        // Highlight strings
        highlightStrings(in: &result, code: code, theme: theme)

        // Highlight numbers
        let numberPattern = #"\b\d+(?:\.\d+)?\b"#
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []) {
            let nsRange = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range, in: code),
                      let attributedRange = Range(range, in: result) else { continue }
                result[attributedRange].foregroundColor = theme.number
            }
        }

        // Highlight comments
        highlightComments(in: &result, code: code, prefix: commentPrefix, multiStart: multilineCommentStart, multiEnd: multilineCommentEnd, theme: theme)

        return result
    }

    private static func highlightStrings(in result: inout AttributedString, code: String, theme: Theme) {
        // Double-quoted strings
        let doubleQuotePattern = #""(?:[^"\\]|\\.)*""#
        if let regex = try? NSRegularExpression(pattern: doubleQuotePattern, options: []) {
            let nsRange = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range, in: code),
                      let attributedRange = Range(range, in: result) else { continue }
                result[attributedRange].foregroundColor = theme.string
            }
        }

        // Single-quoted strings
        let singleQuotePattern = #"'(?:[^'\\]|\\.)*'"#
        if let regex = try? NSRegularExpression(pattern: singleQuotePattern, options: []) {
            let nsRange = NSRange(code.startIndex..., in: code)
            let matches = regex.matches(in: code, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range, in: code),
                      let attributedRange = Range(range, in: result) else { continue }
                result[attributedRange].foregroundColor = theme.string
            }
        }
    }

    private static func highlightComments(in result: inout AttributedString, code: String, prefix: String?, multiStart: String?, multiEnd: String?, theme: Theme) {
        // Single-line comments
        if let prefix = prefix {
            let pattern = "\(NSRegularExpression.escapedPattern(for: prefix)).*$"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                let nsRange = NSRange(code.startIndex..., in: code)
                let matches = regex.matches(in: code, options: [], range: nsRange)

                for match in matches {
                    guard let range = Range(match.range, in: code),
                          let attributedRange = Range(range, in: result) else { continue }
                    result[attributedRange].foregroundColor = theme.comment
                }
            }
        }

        // Multi-line comments
        if let multiStart = multiStart, let multiEnd = multiEnd {
            let escapedStart = NSRegularExpression.escapedPattern(for: multiStart)
            let escapedEnd = NSRegularExpression.escapedPattern(for: multiEnd)
            let pattern = "\(escapedStart)[\\s\\S]*?\(escapedEnd)"

            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(code.startIndex..., in: code)
                let matches = regex.matches(in: code, options: [], range: nsRange)

                for match in matches {
                    guard let range = Range(match.range, in: code),
                          let attributedRange = Range(range, in: result) else { continue }
                    result[attributedRange].foregroundColor = theme.comment
                }
            }
        }
    }
}
