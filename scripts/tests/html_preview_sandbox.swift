// Run with scripts/tests/test_html_preview_sandbox.py; uses the production sandbox.
import AppKit
import Foundation
import WebKit

@main
struct PreviewSandboxCheck {
    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                try await check()
                print("PASS: local interaction, embedded assets, CSP, redirects, frames, forms and network attempts")
                exit(0)
            } catch {
                fputs("FAIL: \(error)\n", stderr)
                exit(1)
            }
        }
        NSApplication.shared.run()
    }

    @MainActor
    static func check() async throws {
        let port = CommandLine.arguments[1]
        let base = "http://localhost:\(port)"
        let control = WKWebView()
        control.load(URLRequest(url: URL(string: "\(base)/positive-webkit-control")!))
        try await waitFor(control, "document.body.textContent.includes('synthetic response')")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 600), configuration: configuration)
        let sandbox = HTMLPreviewSandbox()
        sandbox.attach(to: webView)
        let html = """
        <!DOCTYPE html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src * data: blob: 'unsafe-inline'">
        <link rel="stylesheet" href="\(base)/css">
        <script src="\(base)/script"></script>
        </head><body>
        <button id="button" onclick="window.clicks++">Local control</button>
        <canvas id="canvas" width="2" height="2"></canvas>
        <img id="embedded" src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7">
        <img src="\(base)/image-beacon">
        <iframe src="\(base)/iframe"></iframe>
        <form action="\(base)/form" method="POST"><input name="secret" value="synthetic"></form>
        <script>
          window.clicks = 0;
          const ctx = document.getElementById('canvas').getContext('2d');
          ctx.fillStyle = 'rgb(255,0,0)'; ctx.fillRect(0,0,2,2);
          window.attempts = 0;
          window.exfiltrate = () => {
            window.attempts++;
            fetch('\(base)/fetch?synthetic').catch(() => {});
            const img = new Image(); img.src = '\(base)/dynamic-image';
            try { navigator.sendBeacon('\(base)/beacon', 'synthetic'); } catch (_) {}
            try { new WebSocket('ws://localhost:\(port)/socket'); } catch (_) {}
          };
          window.exfiltrate();
        </script>
        </body></html>
        """
        sandbox.load(html)
        try await waitFor(webView, "window.attempts === 1 && document.getElementById('embedded').naturalWidth === 1")
        try await assertJS(webView, "document.getElementById('canvas').getContext('2d').getImageData(0,0,1,1).data[0] === 255")
        _ = try await evaluate(webView, "document.getElementById('button').click()")
        try await assertJS(webView, "window.clicks === 1 && typeof RTCPeerConnection === 'undefined' && typeof webkitRTCPeerConnection === 'undefined'")

        // A SwiftUI refresh with identical HTML must retain local interaction.
        sandbox.load(html)
        try await assertJS(webView, "window.clicks === 1")
        _ = try await evaluate(webView, "document.querySelector('meta[http-equiv=\"Content-Security-Policy\"]').remove(); window.exfiltrate(); document.forms[0].submit(); window.open('\(base)/popup');")
        _ = try await evaluate(webView, "window.location.href = '\(base)/script-navigation'; undefined")
        try await Task.sleep(nanoseconds: 500_000_000)
        try await assertJS(webView, "window.clicks === 1 && window.attempts === 2 && location.href === 'about:blank'")
        _ = try await evaluate(webView, "window.location.href = 'data:text/html,redirected'; undefined")
        try await Task.sleep(nanoseconds: 200_000_000)
        try await assertJS(webView, "window.clicks === 1 && location.href === 'about:blank'")

        // A new local document remains usable after a cancelled script redirect.
        sandbox.load("<button id='next' onclick='window.nextClicked=true'>Next</button><script>window.nextReady=true</script>")
        try await waitFor(webView, "window.nextReady === true")
        _ = try await evaluate(webView, "document.getElementById('next').click()")
        try await assertJS(webView, "window.nextClicked === true")
    }

    @MainActor
    static func evaluate(_ webView: WKWebView, _ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result) }
            }
        }
    }

    @MainActor
    static func assertJS(_ webView: WKWebView, _ script: String) async throws {
        guard (try await evaluate(webView, script) as? Bool) == true else {
            let state = try? await evaluate(webView, "JSON.stringify({url:location.href,ready:document.readyState,attempts:window.attempts,image:document.getElementById('embedded')?.naturalWidth,html:document.documentElement.outerHTML})")
            print("Synthetic preview state: \(state ?? "unavailable")")
            throw NSError(domain: "HTMLPreviewSandboxCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: script])
        }
    }

    @MainActor
    static func waitFor(_ webView: WKWebView, _ script: String) async throws {
        for _ in 0..<200 {
            if (try? await evaluate(webView, script) as? Bool) == true { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await assertJS(webView, script)
    }
}
