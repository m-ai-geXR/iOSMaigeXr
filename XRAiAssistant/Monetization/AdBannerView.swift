//
//  AdBannerView.swift
//  m{ai}geXR
//
//  Places whatever banner the current provider offers.
//
//  This used to be a UIViewRepresentable returning an AdMob BannerView, which
//  put the network in the view layer. It now places an opaque view and does not
//  know which network produced it.
//

import SwiftUI

/// A banner, or nothing at all.
///
/// Renders empty — taking no space — for a paid user, when consent forbids ads,
/// or when the provider has nothing to serve. Callers can place it
/// unconditionally.
struct AdBannerView: View {
    @ObservedObject private var ads = AdManager.shared

    /// AdMob's standard banner is 320x50. Height is fixed here so the layout
    /// cannot be shifted by whatever the network returns.
    private let bannerHeight: CGFloat = 50

    var body: some View {
        if ads.adsAreServing, let banner = ads.bannerView() {
            banner
                .frame(height: bannerHeight)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Advertisement")
        }
    }
}
