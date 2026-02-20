//
//  AdBannerView.swift
//  m{ai}geXR
//
//  Created: 2026-02-08
//  Purpose: SwiftUI wrapper for AdMob banner ads
//

import SwiftUI
import GoogleMobileAds

/// SwiftUI view that displays an AdMob banner ad
struct AdBannerView: UIViewRepresentable {
    @ObservedObject var adManager = AdManager.shared

    func makeUIView(context: Context) -> BannerView {
        // Get root view controller
        let rootVC = UIApplication.shared.windows.first?.rootViewController ?? UIViewController()

        // Load banner ad from AdManager
        let banner = adManager.loadBannerAd(rootViewController: rootVC)

        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        // No updates needed - banner handles its own refresh
    }
}

/// Preview wrapper for AdBannerView
#Preview {
    VStack {
        Spacer()

        Text("Banner Ad Preview")
            .font(.headline)

        AdBannerView()
            .frame(height: 50)
            .background(Color.gray.opacity(0.2))

        Spacer()
    }
}
