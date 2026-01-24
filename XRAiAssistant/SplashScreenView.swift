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
        .preferredColorScheme(.dark)
    }
}

// MARK: - Preview
#Preview {
    SplashScreenView {
        print("Splash dismissed")
    }
}
