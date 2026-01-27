import SwiftUI
import WebKit

/// A sandboxed HTML preview sheet using WKWebView
struct HTMLPreviewSheet: View {
    let htmlContent: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            HTMLWebView(htmlContent: wrappedHTML, colorScheme: colorScheme)
                .ignoresSafeArea(edges: [.bottom, .horizontal])
                .background(Color.black)
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
        let backgroundColor = colorScheme == .dark ? "#1c1c1e" : "#ffffff"
        let textColor = colorScheme == .dark ? "#ffffff" : "#000000"

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
                    padding: 16px;
                    margin: 0;
                    line-height: 1.5;
                }
                img { max-width: 100%; height: auto; }
                a { color: #007AFF; }
            </style>
        </head>
        <body>
            \(htmlContent)
        </body>
        </html>
        """
    }
}

/// UIViewRepresentable wrapper for WKWebView with sandbox security
struct HTMLWebView: UIViewRepresentable {
    let htmlContent: String
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Enable JavaScript for interactive content (Three.js, Canvas, etc.)
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        // Enable inline media for canvas/WebGL content
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Security: Prevent data persistence
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)

        // Security: Block navigation to external sites
        webView.navigationDelegate = context.coordinator

        // Allow scrolling and interaction
        webView.scrollView.bounces = true

        // Transparent background to match content
        webView.isOpaque = false
        webView.backgroundColor = .clear

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Load HTML from string (no external URLs)
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Coordinator to handle navigation and prevent external links
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Only allow the initial load (about:blank base URL)
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
            } else {
                // Block all navigation attempts (clicks on links, etc.)
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Silently handle navigation failures
        }
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
