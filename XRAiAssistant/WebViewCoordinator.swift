import WebKit
import Foundation
import SwiftUI

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    var parent: PlaygroundWebView

    init(parent: PlaygroundWebView) {
        self.parent = parent
        super.init()
    }

    // MARK: - Console Logging Support

    /// Forward WebKit console messages to Xcode console
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        print("🔔 [WebKit Alert] \(message)")
        completionHandler()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        print("❓ [WebKit Confirm] \(message)")
        completionHandler(true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        print("✏️ [WebKit Prompt] \(prompt)")
        completionHandler(defaultText)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        parent.onWebViewLoaded?()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Handle XPC connection interruptions gracefully
        if let nsError = error as NSError? {
            if nsError.domain == "com.apple.WebKit.Networking" {
                print("⚠️ WebView - WebKit networking error detected, ignoring")
                return
            }

            if nsError.localizedDescription.contains("XPC connection interrupted") {
                print("⚠️ WebView - XPC connection interrupted, ignoring")
                return
            }
        }

        parent.onWebViewError?(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Handle XPC connection interruptions gracefully
        if let nsError = error as NSError? {
            if nsError.domain == "com.apple.WebKit.Networking" {
                print("⚠️ WebView - WebKit networking error detected, ignoring")
                return
            }

            if nsError.localizedDescription.contains("XPC connection interrupted") {
                print("⚠️ WebView - XPC connection interrupted, ignoring")
                return
            }
        }

        parent.onWebViewError?(error)
    }
    
    // Handle messages from JavaScript
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Handle console logging messages
        if message.name == "consoleLogger" {
            if let consoleMessage = message.body as? [String: Any],
               let level = consoleMessage["level"] as? String,
               let messageText = consoleMessage["message"] as? String {

                let emoji: String
                switch level {
                case "error":
                    emoji = "❌"
                case "warn":
                    emoji = "⚠️"
                case "info":
                    emoji = "ℹ️"
                case "debug":
                    emoji = "🐛"
                default:
                    emoji = "📝"
                }

                print("\(emoji) [WebKit Console - \(level.uppercased())] \(messageText)")
            }
            return
        }

        // Handle playground messages
        guard let messageBody = message.body as? [String: Any],
              let action = messageBody["action"] as? String else {
            return
        }

        let data = messageBody["data"] as? [String: Any] ?? [:]

        DispatchQueue.main.async {
            self.parent.handleJavaScriptMessage(action: action, data: data)
        }
    }
}

struct PlaygroundWebView: UIViewRepresentable {
    @Binding var webView: WKWebView?
    var playgroundTemplate: String = "playground"
    var onWebViewLoaded: (() -> Void)?
    var onWebViewError: ((Error) -> Void)?
    var onJavaScriptMessage: ((String, [String: Any]) -> Void)?
    
    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration.createWithAppScheme()
        
        // Configure message handler
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "playgroundHandler")

        // Add console logging interceptor to forward console.log/error/warn to Xcode
        let consoleLogScript = WKUserScript(
            source: """
            (function() {
                const originalLog = console.log;
                const originalError = console.error;
                const originalWarn = console.warn;
                const originalInfo = console.info;
                const originalDebug = console.debug;

                function sendToNative(level, args) {
                    const message = Array.from(args).map(arg => {
                        if (typeof arg === 'object') {
                            try {
                                return JSON.stringify(arg);
                            } catch (e) {
                                return String(arg);
                            }
                        }
                        return String(arg);
                    }).join(' ');

                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.consoleLogger) {
                        window.webkit.messageHandlers.consoleLogger.postMessage({
                            level: level,
                            message: message
                        });
                    }
                }

                console.log = function(...args) {
                    originalLog.apply(console, args);
                    sendToNative('log', args);
                };

                console.error = function(...args) {
                    originalError.apply(console, args);
                    sendToNative('error', args);
                };

                console.warn = function(...args) {
                    originalWarn.apply(console, args);
                    sendToNative('warn', args);
                };

                console.info = function(...args) {
                    originalInfo.apply(console, args);
                    sendToNative('info', args);
                };

                console.debug = function(...args) {
                    originalDebug.apply(console, args);
                    sendToNative('debug', args);
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(consoleLogScript)
        contentController.add(context.coordinator, name: "consoleLogger")

        configuration.userContentController = contentController
        
        // Enable debugging (if needed)
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Allow arbitrary loads for CDN resources
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // Optimize GPU process usage
        configuration.suppressesIncrementalRendering = false
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator // Enable console logging to Xcode
        webView.allowsBackForwardNavigationGestures = false

        // Optimize WebView performance to reduce GPU process exits
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = false
        
        // Load local HTML file - enhanced template loading with multiple fallback strategies
        var htmlLoaded = false
        
        print("🔍 Attempting to load playground template: \(playgroundTemplate)")

        // Nova64's studio runner answers us with postMessage(msg, event.origin).
        // A document loaded from file:// has an opaque origin that serialises to the
        // string "null", which is not a parseable URL — so that call throws inside the
        // runner's EXECUTE_CODE handler BEFORE it evaluates the cart, and the scene
        // just stays blank with no useful error. Giving the page an https base URL
        // gives it a real origin, and makes it same-origin with the runner so the
        // runner's replies actually arrive. playground-nova64.html is fully
        // self-contained for this reason — an https document cannot load app:// or
        // file:// subresources.
        let isNova64Playground = playgroundTemplate.contains("nova64")
        let playgroundBaseURL: URL? = isNova64Playground
            ? URL(string: "https://nova64.io/maigexr-playground/")
            : Bundle.main.resourceURL
        if isNova64Playground {
            print("🎮 Nova64 playground: using https base URL for a non-opaque origin")
        }
        
        // Strategy 1: Try direct bundle resource lookup (templates are in main bundle root)
        if let htmlPath = Bundle.main.path(forResource: playgroundTemplate, ofType: "html") {
            do {
                let htmlContent = try String(contentsOfFile: htmlPath)
                if let baseURL = playgroundBaseURL {
                    print("✅ Loading HTML from main bundle: \(htmlPath)")
                    print("🔗 Base URL: \(baseURL)")
                    webView.loadHTMLString(htmlContent, baseURL: baseURL)
                    htmlLoaded = true
                } else {
                    // Fallback to file URL if no base URL
                    let fileURL = URL(fileURLWithPath: htmlPath)
                    print("✅ Loading HTML with file URL: \(fileURL)")
                    webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
                    htmlLoaded = true
                }
            } catch {
                print("❌ Failed to read HTML content from \(htmlPath): \(error)")
            }
        }
        
        // Strategy 2: Try with template name including .html extension (in case it's missing)
        else if !playgroundTemplate.hasSuffix(".html"),
                let htmlPath = Bundle.main.path(forResource: "\(playgroundTemplate).html", ofType: nil) {
            do {
                let htmlContent = try String(contentsOfFile: htmlPath)
                if let baseURL = playgroundBaseURL {
                    print("✅ Loading HTML with .html extension: \(htmlPath)")
                    webView.loadHTMLString(htmlContent, baseURL: baseURL)
                    htmlLoaded = true
                }
            } catch {
                print("❌ Failed to read HTML with .html extension: \(error)")
            }
        }
        
        // Strategy 3: Search directly in bundle for template files
        else if let resourcePath = Bundle.main.resourcePath {
            // Try to find the exact file by searching bundle contents
            do {
                let bundleContents = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                print("🔍 Bundle contents: \(bundleContents)")
                
                // Look for exact template name or with .html extension
                let possibleNames = [playgroundTemplate, "\(playgroundTemplate).html"]
                for fileName in possibleNames {
                    if bundleContents.contains(fileName) {
                        let fullPath = (resourcePath as NSString).appendingPathComponent(fileName)
                        do {
                            let htmlContent = try String(contentsOfFile: fullPath)
                            if let baseURL = playgroundBaseURL {
                                print("✅ Loading HTML from bundle search: \(fullPath)")
                                webView.loadHTMLString(htmlContent, baseURL: baseURL)
                                htmlLoaded = true
                                break
                            }
                        } catch {
                            print("❌ Failed to read found template \(fullPath): \(error)")
                        }
                    }
                }
            } catch {
                print("❌ Failed to search bundle contents: \(error)")
            }
        }
        
        // Strategy 4: Fallback to playground-babylonjs.html as default (since playground.html was renamed)
        if !htmlLoaded && playgroundTemplate != "playground-babylonjs" {
            print("⚠️ Template \(playgroundTemplate) not found, falling back to playground-babylonjs")
            if let htmlPath = Bundle.main.path(forResource: "playground-babylonjs", ofType: "html") {
                do {
                    let htmlContent = try String(contentsOfFile: htmlPath)
                    if let baseURL = Bundle.main.resourceURL {
                        print("✅ Loading fallback HTML: \(htmlPath)")
                        webView.loadHTMLString(htmlContent, baseURL: baseURL)
                        htmlLoaded = true
                    }
                } catch {
                    print("❌ Failed to load fallback HTML: \(error)")
                }
            }
        }
        
        // Strategy 4: Emergency fallback - create minimal HTML
        if !htmlLoaded {
            print("❌ All template loading strategies failed - creating emergency fallback")
            let emergencyHTML = """
            <!DOCTYPE html>
            <html><head><title>Template Loading Error</title></head>
            <body style="background:#1e1e1e;color:#fff;padding:20px;font-family:system-ui;">
            <h1>Template Loading Error</h1>
            <p>Failed to load playground template: \(playgroundTemplate)</p>
            <p>Please check that the template file exists in the app bundle.</p>
            </body></html>
            """
            webView.loadHTMLString(emergencyHTML, baseURL: nil)
            htmlLoaded = true
            
            // Debug bundle contents for troubleshooting
            if let resourcePath = Bundle.main.resourcePath {
                print("🔍 Bundle resource path: \(resourcePath)")
                do {
                    let bundleContents = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                    print("📁 Bundle contents: \(bundleContents)")
                    
                    let resourcesPath = (resourcePath as NSString).appendingPathComponent("Resources")
                    if FileManager.default.fileExists(atPath: resourcesPath) {
                        let resourcesContents = try FileManager.default.contentsOfDirectory(atPath: resourcesPath)
                        print("📁 Resources directory contents: \(resourcesContents)")
                    }
                } catch {
                    print("❌ Error listing bundle contents: \(error)")
                }
            }
        }
        
        DispatchQueue.main.async {
            self.webView = webView
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No updates needed for now
    }
    
    func handleJavaScriptMessage(action: String, data: [String: Any]) {
        onJavaScriptMessage?(action, data)
    }
}