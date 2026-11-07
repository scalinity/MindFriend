import Foundation
import WebKit

/// Installs the preview's network boundary before loading any supplied HTML.
@MainActor
final class HTMLPreviewSandbox: NSObject, WKNavigationDelegate {
    private weak var webView: WKWebView?
    private var rulesReady = false
    private var pendingHTML: String?
    private var loadedHTML: String?
    private var awaitingInitialNavigation = false

    private static let contentRules = """
    [
      {"trigger":{"url-filter":".*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}},
      {"trigger":{"url-filter":"^blob:"},"action":{"type":"ignore-previous-rules"}},
      {"trigger":{"url-filter":"^about:blank$"},"action":{"type":"ignore-previous-rules"}}
    ]
    """

    private static let policy = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:; connect-src 'none'; frame-src 'none'; child-src 'none'; worker-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'"

    func attach(to webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self

        // Peer connections use sockets rather than ordinary web subresources.
        // Disable their constructors before supplied scripts can obtain them.
        let disablePeerConnections = WKUserScript(source: """
        for (const name of ['RTCPeerConnection', 'webkitRTCPeerConnection']) {
          Object.defineProperty(window, name, { value: undefined, writable: false, configurable: false });
        }
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(disablePeerConnections)

        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "MindFriendLocalHTMLPreview-v1",
            encodedContentRuleList: Self.contentRules
        ) { [weak self, weak webView] rules, error in
            guard let self, let webView else { return }
            guard let rules, error == nil else {
                // Only this constant document may load if the boundary fails.
                self.awaitingInitialNavigation = true
                webView.loadHTMLString("<p>HTML preview is unavailable. Please try again.</p>", baseURL: nil)
                return
            }
            webView.configuration.userContentController.add(rules)
            self.rulesReady = true
            self.loadPendingHTML()
        }
    }

    func load(_ html: String) {
        pendingHTML = html
        loadPendingHTML()
    }

    private func loadPendingHTML() {
        guard rulesReady, let html = pendingHTML, html != loadedHTML, let webView else { return }
        loadedHTML = html
        awaitingInitialNavigation = true
        // Place the policy before every byte of untrusted markup, including
        // complete documents. Later meta tags cannot loosen this policy.
        let document = "<!DOCTYPE html><meta http-equiv=\"Content-Security-Policy\" content=\"\(Self.policy)\"><meta http-equiv=\"x-dns-prefetch-control\" content=\"off\">" + html
        webView.loadHTMLString(document, baseURL: nil)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // A navigation type of .other also includes script redirects. Only
        // consume the one local, main-frame navigation initiated by load().
        if awaitingInitialNavigation,
           navigationAction.navigationType == .other,
           navigationAction.targetFrame?.isMainFrame == true,
           navigationAction.request.url?.absoluteString == "about:blank" {
            awaitingInitialNavigation = false
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }
}
