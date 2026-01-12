import WebKit
import Foundation
import SwiftUI

class CodeSandboxWebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var parent: CodeSandboxWebView

    init(parent: CodeSandboxWebView) {
        self.parent = parent
        super.init()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            print("⚠️ CodeSandbox WebView - Navigation request with no URL")
            decisionHandler(.allow)
            return
        }

        let urlString = url.absoluteString
        print("🌐 CodeSandbox WebView - Navigation request: \(String(urlString.prefix(100)))...")
        print("🔍 Navigation type: \(navigationAction.navigationType.rawValue)")

        // Block obviously malformed URLs (encoded HTML as URL)
        if urlString.hasPrefix("%3C") || urlString.hasPrefix("<") {
            print("❌ CodeSandbox WebView - Blocking malformed URL that appears to be encoded HTML")
            decisionHandler(.cancel)
            return
        }

        // Handle all CodeSandbox domains
        if urlString.contains("codesandbox.io") || urlString.contains(".csb.app") {
            // Capture sandbox URL if it contains /s/ path (editor URL)
            if urlString.contains("/s/") {
                let sandboxURL = urlString
                print("🎯 CodeSandbox WebView - Captured sandbox URL: \(sandboxURL)")

                DispatchQueue.main.async {
                    self.parent.currentSandboxURL = sandboxURL
                    self.parent.onSandboxCreated?(sandboxURL)
                }
            }

            print("✅ CodeSandbox WebView - Allowing navigation to: \(urlString)")
            decisionHandler(.allow)
            return
        }

        // Allow local content (about:blank for our form)
        if urlString.hasPrefix("file://") || urlString.hasPrefix("about:") {
            print("✅ CodeSandbox WebView - Allowing local content")
            decisionHandler(.allow)
            return
        }

        // Allow form submissions by default
        print("✅ CodeSandbox WebView - Allowing navigation (type: \(navigationAction.navigationType.rawValue))")
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ CodeSandbox WebView - Navigation finished")
        parent.onWebViewLoaded?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ CodeSandbox WebView - Navigation failed: \(error)")

        // Handle XPC connection interruptions gracefully
        if let nsError = error as NSError? {
            if nsError.domain == "com.apple.WebKit.Networking" {
                print("⚠️ CodeSandbox WebView - WebKit networking error detected, ignoring")
                return
            }

            if nsError.localizedDescription.contains("XPC connection interrupted") {
                print("⚠️ CodeSandbox WebView - XPC connection interrupted, attempting recovery")

                // Give the WebView a moment to recover
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Don't propagate XPC errors to the UI
                    print("🔄 CodeSandbox WebView - XPC interruption handled gracefully")
                }
                return
            }
        }

        parent.onWebViewError?(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ CodeSandbox WebView - Provisional navigation failed: \(error)")

        // Handle different types of navigation errors
        if let nsError = error as NSError? {
            switch (nsError.domain, nsError.code) {
            case ("WebKitErrorDomain", 101):
                print("⚠️ CodeSandbox WebView - Detected URL encoding issue (malformed URL)")
                print("🔄 This should be resolved by the new JavaScript form creation approach")
                return

            case ("NSURLErrorDomain", -999):
                print("⚠️ CodeSandbox WebView - Navigation cancelled (Code -999)")
                print("🔄 This is often normal during form submission - ignoring")
                return

            case ("com.apple.WebKit.Networking", _):
                print("⚠️ CodeSandbox WebView - WebKit networking error - ignoring")
                return

            default:
                print("❌ CodeSandbox WebView - Unhandled error: domain=\(nsError.domain), code=\(nsError.code)")
            }
        }

        // Only propagate errors that we haven't specifically handled
        parent.onWebViewError?(error)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "codeSandboxDebug":
            print("📱 CodeSandbox WebView - JavaScript: \(message.body)")
        case "consoleLog":
            print("🟦 WebView console.log: \(message.body)")
        case "consoleError":
            print("🟥 WebView console.error: \(message.body)")
        default:
            print("📱 WebView message [\(message.name)]: \(message.body)")
        }
    }
}

struct CodeSandboxWebView: UIViewRepresentable {
    @Binding var webView: WKWebView?
    var framework: String = "react-three-fiber"
    var onWebViewLoaded: (() -> Void)?
    var onWebViewError: ((Error) -> Void)?
    var onSandboxCreated: ((String) -> Void)?
    var onTriggerCreate: (@escaping (String) -> Void) -> Void  // Callback that provides a creation function

    @State var currentSandboxURL: String?
    @State private var isCreatingSandbox = false

    func makeCoordinator() -> CodeSandboxWebViewCoordinator {
        CodeSandboxWebViewCoordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Enable debugging
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Enable JavaScript
        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        } else {
            configuration.preferences.javaScriptEnabled = true
        }

        // Add message handlers for debugging
        configuration.userContentController.add(context.coordinator, name: "codeSandboxDebug")
        configuration.userContentController.add(context.coordinator, name: "consoleLog")
        configuration.userContentController.add(context.coordinator, name: "consoleError")
        
        // Inject console.log/error interceptors for debugging
        let consoleScript = """
        (function() {
            const originalLog = console.log;
            const originalError = console.error;
            const originalWarn = console.warn;
            
            console.log = function(...args) {
                window.webkit.messageHandlers.consoleLog.postMessage(args.join(' '));
                originalLog.apply(console, args);
            };
            
            console.error = function(...args) {
                window.webkit.messageHandlers.consoleError.postMessage(args.join(' '));
                originalError.apply(console, args);
            };
            
            console.warn = function(...args) {
                window.webkit.messageHandlers.consoleLog.postMessage('[WARN] ' + args.join(' '));
                originalWarn.apply(console, args);
            };
            
            // Catch unhandled errors
            window.addEventListener('error', function(e) {
                window.webkit.messageHandlers.consoleError.postMessage('Uncaught error: ' + e.message + ' at ' + e.filename + ':' + e.lineno);
            });
        })();
        """
        
        let userScript = WKUserScript(source: consoleScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false

        print("🌐 CodeSandbox WebView - Created with configuration and console logging")

        // Load initial placeholder
        loadPlaceholder(webView: webView)

        DispatchQueue.main.async {
            self.webView = webView
            
            // Provide the creation function via callback
            self.onTriggerCreate { code in
                // This closure will be called from ContentView when code is ready
                self.createAndLoadSandbox(code: code)
            }
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Updates handled by external injection methods
    }

    // MARK: - Public API

    func createAndLoadSandbox(code: String) {
        guard let webView = webView, !isCreatingSandbox else {
            print("⚠️ CodeSandbox WebView - Cannot create sandbox: WebView not ready or already creating")
            return
        }

        isCreatingSandbox = true
        print("🚀 CodeSandbox WebView - Creating sandbox using NATIVE API CLIENT")
        print("🔧 Framework: \(framework)")
        print("📝 Code length: \(code.count) characters")

        // Show loading state immediately
        showLoadingState(webView: webView, message: "Creating CodeSandbox via native API...")

        // Use native Swift HTTP client instead of WKWebView form submission
        Task {
            do {
                print("📡 Making native URLSession request to CodeSandbox API...")
                let sandboxURL = try await CodeSandboxAPIClient.shared.createSandbox(
                    code: code,
                    framework: framework
                )
                
                print("✅ CodeSandbox created successfully: \(sandboxURL)")
                
                // Update UI on main thread
                await MainActor.run {
                    self.currentSandboxURL = sandboxURL
                    self.loadSandbox(webView: webView, url: sandboxURL)
                    self.onSandboxCreated?(sandboxURL)
                    self.isCreatingSandbox = false
                }
            } catch {
                print("❌ CodeSandbox creation failed: \(error.localizedDescription)")
                
                // Show error in WebView
                await MainActor.run {
                    self.showError(webView: webView, error: error)
                    self.onWebViewError?(error)
                    self.isCreatingSandbox = false
                }
            }
        }
    }

    func isReady() -> Bool {
        return webView != nil && !isCreatingSandbox
    }

    func getCurrentCode() -> String {
        // For CodeSandbox, we don't track code locally - it's in the sandbox
        return ""
    }

    // MARK: - Private Methods

    private func loadPlaceholder(webView: WKWebView) {
        let placeholderHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>XRAiAssistant - CodeSandbox</title>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }

                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                    height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    text-align: center;
                }

                .container {
                    max-width: 400px;
                    padding: 40px 20px;
                }

                .logo {
                    font-size: 48px;
                    margin-bottom: 20px;
                }

                .title {
                    font-size: 24px;
                    font-weight: 600;
                    margin-bottom: 16px;
                }

                .description {
                    font-size: 16px;
                    opacity: 0.9;
                    line-height: 1.5;
                    margin-bottom: 32px;
                }

                .status {
                    display: inline-block;
                    background: rgba(255, 255, 255, 0.2);
                    padding: 8px 16px;
                    border-radius: 20px;
                    font-size: 14px;
                    font-weight: 500;
                }

                .loading {
                    display: inline-block;
                    width: 20px;
                    height: 20px;
                    border: 2px solid rgba(255, 255, 255, 0.3);
                    border-radius: 50%;
                    border-top-color: white;
                    animation: spin 1s ease-in-out infinite;
                    margin-right: 8px;
                    vertical-align: middle;
                }

                @keyframes spin {
                    to { transform: rotate(360deg); }
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="logo">🎨</div>
                <div class="title">XRAiAssistant CodeSandbox</div>
                <div class="description">
                    Ready to create live \(framework == "reactThreeFiber" ? "React Three Fiber" : "Reactylon") sandboxes.<br>
                    Generate AI code to see it running in a real development environment!
                </div>
                <div class="status">
                    <span class="loading"></span>
                    Waiting for AI code...
                </div>
            </div>
        </body>
        </html>
        """

        webView.loadHTMLString(placeholderHTML, baseURL: Bundle.main.bundleURL)
    }
    
    private func showLoadingState(webView: WKWebView, message: String) {
        let loadingHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Creating CodeSandbox...</title>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                    height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    text-align: center;
                }
                
                .container {
                    max-width: 400px;
                    padding: 40px 20px;
                }
                
                .spinner {
                    border: 4px solid rgba(255, 255, 255, 0.3);
                    border-radius: 50%;
                    border-top-color: white;
                    width: 48px;
                    height: 48px;
                    animation: spin 1s linear infinite;
                    margin: 0 auto 24px;
                }
                
                @keyframes spin {
                    to { transform: rotate(360deg); }
                }
                
                h2 {
                    font-size: 24px;
                    margin-bottom: 12px;
                }
                
                p {
                    font-size: 16px;
                    opacity: 0.9;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="spinner"></div>
                <h2>🚀 Creating CodeSandbox...</h2>
                <p>\(message)</p>
            </div>
        </body>
        </html>
        """
        
        webView.loadHTMLString(loadingHTML, baseURL: nil)
    }
    
    private func showError(webView: WKWebView, error: Error) {
        let errorHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>CodeSandbox Error</title>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    background: linear-gradient(135deg, #ff6b6b 0%, #ee5a6f 100%);
                    color: white;
                    height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    text-align: center;
                    padding: 20px;
                }
                
                .container {
                    max-width: 500px;
                    background: rgba(0, 0, 0, 0.2);
                    padding: 32px;
                    border-radius: 12px;
                }
                
                .icon {
                    font-size: 48px;
                    margin-bottom: 16px;
                }
                
                h2 {
                    font-size: 24px;
                    margin-bottom: 12px;
                }
                
                .error-message {
                    font-size: 14px;
                    opacity: 0.9;
                    margin-bottom: 24px;
                    font-family: 'Courier New', monospace;
                    background: rgba(0, 0, 0, 0.2);
                    padding: 12px;
                    border-radius: 6px;
                }
                
                .suggestions {
                    text-align: left;
                    font-size: 14px;
                    line-height: 1.6;
                }
                
                .suggestions li {
                    margin-bottom: 8px;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="icon">⚠️</div>
                <h2>Failed to Create CodeSandbox</h2>
                <div class="error-message">\(error.localizedDescription)</div>
                <div class="suggestions">
                    <strong>Troubleshooting:</strong>
                    <ul>
                        <li>Check your internet connection</li>
                        <li>Verify CodeSandbox API key in Settings</li>
                        <li>Try regenerating the code</li>
                        <li>Check the Xcode console for detailed logs</li>
                    </ul>
                </div>
            </div>
        </body>
        </html>
        """
        
        webView.loadHTMLString(errorHTML, baseURL: nil)
    }

    private func loadSandbox(webView: WKWebView, url: String) {
        // Extract sandbox ID from the URL
        var sandboxID: String?

        if url.contains("/s/") {
            // URL format: https://codesandbox.io/s/abc123
            if let range = url.range(of: "/s/") {
                let afterSlash = url[range.upperBound...]
                sandboxID = String(afterSlash.split(separator: "/").first ?? "")
            }
        } else if url.contains("/p/sandbox/") {
            // URL format: https://codesandbox.io/p/sandbox/abc123
            if let range = url.range(of: "/p/sandbox/") {
                let afterSlash = url[range.upperBound...]
                sandboxID = String(afterSlash.split(separator: "/").first ?? "")
            }
        }

        guard let id = sandboxID, !id.isEmpty else {
            print("❌ CodeSandbox WebView - Could not extract sandbox ID from: \(url)")
            return
        }

        // FIX: Use CodeSandbox EMBED URL (matches Android exactly)
        // The embed URL provides swipe-to-reveal editor functionality
        // Android uses: https://codesandbox.io/embed/{id}?view=preview&hidenavigation=1
        let embedURL = "https://codesandbox.io/embed/\(id)?view=preview&hidenavigation=1"
        
        // The full sandbox URL is already passed via onSandboxCreated callback in createAndLoadSandbox
        let fullSandboxURL = "https://codesandbox.io/s/\(id)"

        print("🌐 CodeSandbox WebView - Loading embed (matches Android): \(embedURL)")
        print("🔗 Full sandbox URL for browser: \(fullSandboxURL)")
        print("✅ Embed mode with swipe-to-reveal editor")

        if let url = URL(string: embedURL) {
            webView.load(URLRequest(url: url))
        }
    }

}

// MARK: - API Compatibility Layer

extension CodeSandboxWebView {
    // Compatibility methods for existing injection system
    func setFullEditorContent(_ code: String) async -> Bool {
        createAndLoadSandbox(code: code)
        return true
    }

    func executeJavaScript(_ script: String) async -> String? {
        // For CodeSandbox approach, we don't execute arbitrary JavaScript
        // Instead, we create new sandboxes with updated code
        return nil
    }
}