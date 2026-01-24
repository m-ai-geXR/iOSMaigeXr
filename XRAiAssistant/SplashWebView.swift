//
//  SplashWebView.swift
//  m{ai}geXR
//
//  UIViewRepresentable wrapper for splash screen WebView
//  Handles loading splash.html and dismiss message handling
//

import SwiftUI
import WebKit

struct SplashWebView: UIViewRepresentable {
    @Binding var webView: WKWebView?
    var onDismiss: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        // Configure WebView with message handler
        let config = WKWebViewConfiguration()
        config.userContentController.add(
            context.coordinator,
            name: "splashHandler"
        )

        // Allow inline media playback
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Create WebView
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1.0) // cyberpunkBlack
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false

        // Set navigation delegate for debugging
        wv.navigationDelegate = context.coordinator

        // Load splash.html from bundle
        if let url = Bundle.main.url(forResource: "splash", withExtension: "html") {
            print("🚀 Loading splash screen from: \(url.path)")
            wv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            print("❌ Failed to find splash.html in bundle")

            // Fallback: Load emergency HTML
            let fallbackHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                    body {
                        margin: 0;
                        background: #0A0A0A;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        height: 100vh;
                        font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    }
                    .logo {
                        font-size: 64px;
                        font-weight: 700;
                        letter-spacing: 2px;
                    }
                    .m-text, .ge-text { color: #00FFF9; }
                    .ai-text { color: #FF00C1; }
                </style>
            </head>
            <body ontouchend="window.webkit.messageHandlers.splashHandler.postMessage({action:'dismiss'})">
                <div class="logo">
                    <span class="m-text">m</span><span class="ai-text">{ai}</span><span class="ge-text">geXR</span>
                </div>
            </body>
            </html>
            """
            wv.loadHTMLString(fallbackHTML, baseURL: nil)
        }

        // Store reference
        DispatchQueue.main.async {
            self.webView = wv
        }

        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
            super.init()
        }

        // Handle messages from JavaScript
        func userContentController(_ userContentController: WKUserContentController,
                                  didReceive message: WKScriptMessage) {
            if message.name == "splashHandler" {
                if let body = message.body as? [String: Any],
                   body["action"] as? String == "dismiss" {
                    print("🎯 Splash dismiss message received")
                    DispatchQueue.main.async {
                        self.onDismiss()
                    }
                }
            }
        }

        // Navigation delegate methods for debugging
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("✅ Splash WebView finished loading")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ Splash WebView failed to load: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView,
                    didFailProvisionalNavigation navigation: WKNavigation!,
                    withError error: Error) {
            print("❌ Splash WebView provisional navigation failed: \(error.localizedDescription)")
        }

        // Console logging (forward to Xcode console)
        func webView(_ webView: WKWebView,
                    runJavaScriptAlertPanelWithMessage message: String,
                    initiatedByFrame frame: WKFrameInfo,
                    completionHandler: @escaping () -> Void) {
            print("🌐 Splash JS Alert: \(message)")
            completionHandler()
        }
    }
}
