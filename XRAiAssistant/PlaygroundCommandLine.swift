import Foundation
import WebKit

/// The scene command line: a one-line JavaScript console at the bottom of the
/// playground. The script (Resources/playground-commandline.js) is shared with
/// Android; this injects it and applies the Settings toggle.
enum PlaygroundCommandLine {
    /// UserDefaults key behind the Settings toggle. On unless the user turns it off.
    static let enabledKey = "XRAiAssistant_CommandLineEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static let script: String? = {
        guard let url = Bundle.main.url(forResource: "playground-commandline", withExtension: "js") else {
            print("⚠️ playground-commandline.js missing from the bundle")
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    /// Injects the command line into a freshly loaded playground page. CodeSandbox
    /// previews are a third-party page and are left alone.
    static func inject(into webView: WKWebView) {
        if webView.url?.host?.contains("codesandbox") == true { return }
        guard let script else { return }
        webView.evaluateJavaScript(script + "\n;" + toggleJS(), completionHandler: nil)
    }

    /// Shows or hides an already injected command line to match the setting.
    static func applySetting(to webView: WKWebView) {
        webView.evaluateJavaScript(toggleJS(), completionHandler: nil)
    }

    private static func toggleJS() -> String {
        "window.maigeCommandLine && window.maigeCommandLine.setEnabled(\(isEnabled));"
    }
}
