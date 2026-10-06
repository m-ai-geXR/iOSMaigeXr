//
//  AdMobProvider.swift
//  m{ai}geXR
//
//  AdMob behind the AdProvider seam.
//
//  This is the only file in the app that imports GoogleMobileAds. If that stops
//  being true, the abstraction has leaked — see AdProvider.swift.
//

import SwiftUI
import GoogleMobileAds

@MainActor
final class AdMobProvider: NSObject, AdProvider {

    let name = "AdMob"
    private(set) var isAvailable = false

    private var consent: AdConsent = .unknown
    private var interstitial: InterstitialAd?
    private var started = false

    // MARK: - Lifecycle

    func initialize(consent: AdConsent) async {
        self.consent = consent

        // No consent, or consent refused, means nothing may load. Not an error.
        guard consent.allowsAds else {
            log("consent does not allow ads (\(consent)); not starting")
            return
        }

        // The SDK itself only needs starting once; a later call just refreshes
        // availability.
        if !started {
            started = true
            await MobileAds.shared.start()
            log("started")
        }

        isAvailable = true
        await preload(.interstitial)
    }

    func updateConsent(_ consent: AdConsent) {
        self.consent = consent

        // Drop anything prepared under the previous decision rather than show a
        // personalised ad to someone who has just declined.
        interstitial = nil

        if !consent.allowsAds {
            isAvailable = false
        }
    }

    // MARK: - Banner

    func bannerView() -> AnyView? {
        guard isAvailable, consent.allowsAds else { return nil }
        return AnyView(AdMobBannerRepresentable(unitID: AdUnits.banner, request: makeRequest()))
    }

    // MARK: - Preloading

    func preload(_ format: AdFormat) async {
        guard isAvailable, consent.allowsAds else { return }

        switch format {
        case .banner:
            break // banners load themselves when placed
        case .interstitial:
            guard interstitial == nil else { return }
            guard !AdUnits.interstitial.isEmpty else {
                log("no interstitial unit configured")
                return
            }
            interstitial = try? await InterstitialAd.load(
                with: AdUnits.interstitial,
                request: makeRequest()
            )
            interstitial?.fullScreenContentDelegate = self
            log(interstitial == nil ? "interstitial failed to load" : "interstitial ready")
        }
    }

    // MARK: - Full screen

    @discardableResult
    func showInterstitial(from presenter: UIViewController?) async -> Bool {
        guard let presenter, let ad = interstitial else { return false }

        ad.present(from: presenter)
        interstitial = nil
        Task { await preload(.interstitial) }   // ready for next time
        return true
    }

    // MARK: - Internals

    private func makeRequest() -> Request {
        let request = Request()
        if consent == .nonPersonalised {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
        }
        return request
    }

    private func log(_ message: String) {
        if AppConfig.showAdDebugLogs { print("🎯 AdMob: \(message)") }
    }
}

// MARK: - Full screen delegate

extension AdMobProvider: FullScreenContentDelegate {
    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in
            log("failed to present: \(error.localizedDescription)")
            interstitial = nil
            await preload(.interstitial)
        }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            log("dismissed")
            await preload(.interstitial)
        }
    }
}

// MARK: - Banner bridge

/// Wraps AdMob's banner so the app can place it as an ordinary SwiftUI view.
private struct AdMobBannerRepresentable: UIViewRepresentable {
    let unitID: String
    let request: Request

    func makeUIView(context: Context) -> BannerView {
        let view = BannerView(adSize: adSizeFor(cgSize: CGSize(width: 320, height: 50)))
        view.adUnitID = unitID
        view.rootViewController = UIApplication.shared.topMostViewController
        view.load(request)
        return view
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}

// MARK: - Ad unit IDs

/// Google's public sample units on debug, real units on release.
///
/// The release values come from Info.plist and are **empty until the AdMob
/// account has live units**; shipping without them is a release blocker,
/// recorded in docs/release/READINESS-AUDIT.md. Empty is handled rather than
/// shipped as a crash: `preload` declines and the app serves nothing.
///
/// Test units ship on debug deliberately — serving live ads to a development
/// device risks the AdMob account.
enum AdUnits {
    #if DEBUG
    static let banner = "ca-app-pub-3940256099942544/2934735716"
    static let interstitial = "ca-app-pub-3940256099942544/4411468910"
    #else
    static let banner = Bundle.main.object(forInfoDictionaryKey: "GADBannerUnitID") as? String ?? ""
    static let interstitial = Bundle.main.object(forInfoDictionaryKey: "GADInterstitialUnitID") as? String ?? ""
    #endif
}
