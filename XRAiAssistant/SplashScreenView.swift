//
//  SplashScreenView.swift
//  m{ai}geXR
//
//  SwiftUI view wrapper for the vaporwave splash screen
//  Displays on app launch with animated Three.js scene
//

import SwiftUI
import WebKit

struct SplashScreenView: View {
    var onDismiss: () -> Void
    @State private var webView: WKWebView?

    var body: some View {
        ZStack {
            // Background color (cyberpunkBlack) while WebView loads
            Color(red: 0.039, green: 0.039, blue: 0.039)
                .ignoresSafeArea()

            // Splash WebView
            SplashWebView(webView: $webView, onDismiss: onDismiss)
                .ignoresSafeArea()
        }
        // environment, not preferredColorScheme: the latter propagates up to the
        // window, so while the splash was on screen it forced the whole app dark
        // and the user's Light choice did not apply.
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Preview
#Preview {
    SplashScreenView {
        print("Splash dismissed")
    }
}
