import SwiftUI
import WebKit
import TinyKit

struct MarkdownPreviewView: NSViewRepresentable {
    let html: String
    var baseURL: URL?
    var scrollBridge: ScrollBridge
    var syncScroll: Bool = false

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.baseURL = baseURL
        context.coordinator.loadTemplate(in: webView, baseURL: baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // If the base URL changed (different file/folder), reload the template
        if context.coordinator.baseURL != baseURL {
            context.coordinator.baseURL = baseURL
            context.coordinator.loadTemplate(in: webView, baseURL: baseURL)
        }

        context.coordinator.pendingHTML = html
        context.coordinator.scheduleUpdate()

        if syncScroll {
            scrollBridge.onScroll = { [weak coordinator = context.coordinator] fraction in
                coordinator?.scrollTo(fraction: fraction)
            }
        } else {
            scrollBridge.onScroll = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        var baseURL: URL?
        var pendingHTML: String = ""
        private var debounceTask: DispatchWorkItem?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            injectAccentColor()
            pushHTML()
        }

        /// Intercept link clicks — open in default browser instead of the preview pane
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func loadTemplate(in webView: WKWebView, baseURL: URL?) {
            webView.loadHTMLString(Self.templateHTML, baseURL: baseURL)
        }

        private func injectAccentColor() {
            guard let webView else { return }
            let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.controlAccentColor
            let r = Int(color.redComponent * 255)
            let g = Int(color.greenComponent * 255)
            let b = Int(color.blueComponent * 255)
            let hex = String(format: "#%02x%02x%02x", r, g, b)
            let js = "document.documentElement.style.setProperty('--link', '\(hex)')"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func scheduleUpdate() {
            debounceTask?.cancel()
            let task = DispatchWorkItem { [weak self] in
                self?.pushHTML()
            }
            debounceTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
        }

        func scrollTo(fraction: CGFloat) {
            let js = "document.documentElement.scrollTop = \(fraction) * (document.documentElement.scrollHeight - document.documentElement.clientHeight)"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        private func pushHTML() {
            guard let webView else { return }

            let escaped = pendingHTML
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "${", with: "\\${")

            let js = "updateContent(`\(escaped)`)"

            webView.evaluateJavaScript(js) { [weak self] _, error in
                if error != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.pushHTML()
                    }
                }
            }
        }

        // MARK: - Template loaded from bundle resource

        private static let templateHTML: String = {
            if let url = Bundle.main.url(forResource: "preview", withExtension: "html"),
               let html = try? String(contentsOf: url, encoding: .utf8) {
                return html
            }
            // Minimal fallback if resource can't be loaded
            return """
            <!DOCTYPE html><html><head><meta charset="utf-8"></head>
            <body><div id="content"></div>
            <script>function updateContent(h){document.getElementById('content').innerHTML=h}</script>
            </body></html>
            """
        }()
    }
}
