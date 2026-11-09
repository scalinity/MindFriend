import SwiftUI
import WebKit
import UIKit

/// A sandboxed HTML preview sheet using WKWebView
struct HTMLPreviewSheet: View {
    let htmlContent: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        NavigationStack {
            HTMLWebView(htmlContent: wrappedHTML, colorScheme: colorScheme)
                .ignoresSafeArea(edges: [.bottom, .horizontal])
                .background(SupportTheme.surface)
                .foregroundStyle(SupportTheme.textPrimary)
                .supportSheet()
                .navigationTitle("HTML Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }

    /// Wrap the HTML content with proper document structure and styling
    /// If content is already a full HTML document, use it directly
    private var wrappedHTML: String {
        // Check if content is already a complete HTML document
        let trimmed = htmlContent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<!doctype") || trimmed.hasPrefix("<html") {
            return htmlContent
        }

        // Wrap fragment in basic HTML structure
        let backgroundColor = cssColor(SupportTheme.canvas)
        let textColor = cssColor(SupportTheme.textPrimary)
        let linkColor = cssColor(SupportTheme.accent)

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    background-color: \(backgroundColor);
                    color: \(textColor);
                    padding: \(SupportTheme.Spacing.m)px;
                    margin: 0;
                    line-height: 1.5;
                }
                img { max-width: 100%; height: auto; }
                a { color: \(linkColor); }
            </style>
        </head>
        <body>
            \(htmlContent)
        </body>
        </html>
        """
    }

    private func cssColor(_ color: Color) -> String {
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light),
            UITraitCollection(accessibilityContrast: colorSchemeContrast == .increased ? .high : .normal)
        ])
        let resolved = UIColor(color).resolvedColor(with: traits)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return "rgba(\(Int(red * 255)), \(Int(green * 255)), \(Int(blue * 255)), \(alpha))"
    }
}

/// UIViewRepresentable wrapper for WKWebView with sandbox security
struct HTMLWebView: UIViewRepresentable {
    let htmlContent: String
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Keep inline JavaScript available for local interactive content.
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        // Enable inline media for canvas/WebGL content
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Security: Prevent data persistence
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)

        // Install network rules before any supplied document is loaded.
        context.coordinator.attach(to: webView)

        // Allow scrolling and interaction
        webView.scrollView.bounces = true

        // Transparent background to match content
        webView.isOpaque = false
        webView.backgroundColor = .clear

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(htmlContent)
    }

    func makeCoordinator() -> HTMLPreviewSandbox {
        HTMLPreviewSandbox()
    }
}

#Preview {
    HTMLPreviewSheet(htmlContent: """
        <div style="text-align: center;">
            <h1 style="color: #007AFF;">Hello World!</h1>
            <p>This is a <strong>preview</strong> of your HTML code.</p>
            <button style="padding: 10px 20px; border-radius: 8px; border: none; background: #007AFF; color: white;">
                Click Me
            </button>
        </div>
    """)
}
