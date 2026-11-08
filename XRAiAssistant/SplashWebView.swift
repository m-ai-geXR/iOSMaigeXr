import SwiftUI
import WebKit

/// Bundled identity with a hosted Nova64 cart. Navigation only exposes dismissal.
struct SplashWebView: UIViewRepresentable {
    @Binding var webView: WKWebView?
    var onDismiss: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.addUserScript(WKUserScript(
            source: "window.splashNativeHost = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 11/255, green: 13/255, blue: 18/255, alpha: 1)
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.navigationDelegate = context.coordinator
        context.coordinator.startDeadline()
        if let url = Bundle.main.url(forResource: "splash", withExtension: "html"),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            // A real origin lets the Nova64 studio protocol reply to this page.
            // Mascot and font are data URLs inside the bundled HTML for offline use.
            view.loadHTMLString(html, baseURL: URL(string: "https://nova64.io/"))
        } else {
            view.loadHTMLString("""
            <html><body style="background:#0b0d12;color:#f3f2f2;font: bold 42px Arial">
            <h1>m<span style="color:#3f6bf0">{ai}</span>geXR</h1>
            <p style="font-size:20px">Imagine. Make. Play.</p>
            </body></html>
            """, baseURL: nil)
        }
        DispatchQueue.main.async { self.webView = view }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onDismiss = onDismiss
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelDeadline()
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.loadHTMLString("", baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    class Coordinator: NSObject, WKNavigationDelegate {
        var onDismiss: () -> Void
        private var deadline: DispatchWorkItem?
        private var dismissed = false

        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func startDeadline() {
            let task = DispatchWorkItem { [weak self] in self?.dismiss() }
            deadline = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: task)
        }

        func cancelDeadline() { deadline?.cancel(); deadline = nil }

        private func dismiss() {
            guard !dismissed else { return }
            dismissed = true
            cancelDeadline()
            onDismiss()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame?.isMainFrame == true,
               navigationAction.request.url?.absoluteString == "maigexr://splash/dismiss" {
                decisionHandler(.cancel)
                dismiss()
                return
            }
            // Keep the top-level splash local; only its runtime subframe navigates.
            if navigationAction.targetFrame?.isMainFrame == true,
               let url = navigationAction.request.url,
               url.absoluteString != "about:blank", url.absoluteString != "https://nova64.io/" {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
