//
//  SplashScreenView.swift
//  m{ai}geXR
//
//  SwiftUI view wrapper for the m{ai}geXR brand intro
//  Displays on app launch with a Nova64 portal cart
//

import SwiftUI
import WebKit

struct SplashScreenView: View {
    var onDismiss: () -> Void
    @State private var webView: WKWebView?

    var body: some View {
        ZStack {
            // Brand background while the bundled identity loads
            Color(red: 11/255, green: 13/255, blue: 18/255)
                .ignoresSafeArea()

            // Splash WebView
            SplashWebView(webView: $webView, onDismiss: onDismiss)
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
