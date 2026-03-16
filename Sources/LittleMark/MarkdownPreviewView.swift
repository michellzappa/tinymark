import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let html: String
    var baseURL: URL?
    var scrollBridge: ScrollBridge
    var syncScroll: Bool = false

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        // Load preview.html from bundle, granting read access to user's files
        // so relative image paths in markdown work
        if let url = Bundle.main.url(forResource: "preview", withExtension: "html") {
            // Grant read access to root so both the bundle template and user's images are accessible
            webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        }

        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.baseURL = baseURL
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // If the base URL changed (different file/folder), reload the shell
        // so WKWebView gets read access to the new directory
        if context.coordinator.baseURL != baseURL {
            context.coordinator.baseURL = baseURL
            context.coordinator.pageReady = false
            if let url = Bundle.main.url(forResource: "preview", withExtension: "html") {
                webView.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
            }
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
        var pageReady = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageReady = true
            // Inject the system accent color so links match the editor
            injectAccentColor()
            // Push any content that was queued while loading
            if !pendingHTML.isEmpty {
                pushHTML()
            }
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
            guard pageReady else { return } // Wait for didFinish
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

            // Set <base> in <head> so relative image/link paths resolve correctly
            if let base = baseURL {
                let baseJS = "var b = document.querySelector('base'); if (!b) { b = document.createElement('base'); document.head.appendChild(b); } b.href = `\(base.absoluteString)`;"
                webView.evaluateJavaScript(baseJS, completionHandler: nil)
            }

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
    }
}
