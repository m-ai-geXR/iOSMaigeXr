//
//  AdProvider.swift
//  m{ai}geXR
//
//  The seam between the app and whichever ad network is in use.
//
//  AdManager previously imported GoogleMobileAds and published AdMob types in
//  its own API, so the network was baked into every call site and swapping it
//  meant editing the manager and everything touching it.
//
//  Nothing network-specific may appear in this file. The moment a BannerView or
//  a GADRequest appears in one of these signatures the abstraction has leaked
//  and the swap stops being cheap. A banner is an opaque view the app places; it
//  is not an AdMob object.
//

import SwiftUI

/// Which ad format a placement is asking for.
///
/// Rewarded ads are deliberately absent. They were cut from v1 because the
/// rewards the old code offered — premium model access, GLB/FBX/USD export,
/// cloud sync, unlimited favourites — pointed at features that are not built.
/// Bringing them back means a case here plus a method on the protocol, which is
/// the point: it should be a deliberate change, not dormant code.
enum AdFormat {
    case banner
    case interstitial
}

/// What the user has agreed to.
///
/// Resolved once, above the provider, and passed down. Each adapter translates
/// it into whatever its own SDK wants. Declining is a normal outcome, not an
/// error: a user who refuses personalisation still gets non-personalised ads,
/// and a user who refuses ads outright simply gets none.
enum AdConsent {
    /// Consent not gathered yet. Providers must not load anything.
    case unknown
    /// Ads refused, or required consent was not given. No ads at all.
    case denied
    /// Ads allowed, but without a tracking identifier.
    case nonPersonalised
    /// Ads allowed and personalised.
    case personalised

    /// The only question a provider needs to ask of consent.
    ///
    /// `denied` and `unknown` both mean "load nothing", but they are kept apart
    /// because they are not the same thing: one is a decision, the other is the
    /// absence of one. Collapsing them loses the ability to tell "the user said
    /// no" from "we have not asked yet".
    var allowsAds: Bool {
        switch self {
        case .personalised, .nonPersonalised: return true
        case .unknown, .denied: return false
        }
    }
}

/// One ad network, behind a stable interface.
///
/// Implementations must fail soft. A provider that cannot start returns no ads
/// and reports `isAvailable == false`; it must never crash or block the UI,
/// because this is third-party code on the startup path.
///
/// Pacing is not here on purpose. How often an ad may appear is a product rule
/// and lives in `AdManager`, so every network inherits it and swapping one
/// cannot quietly change how often users see ads.
@MainActor
protocol AdProvider: AnyObject {
    /// For logs and diagnostics. Not shown to users.
    var name: String { get }

    /// False when the SDK failed to start, or there is nothing to serve.
    var isAvailable: Bool { get }

    /// Start the SDK. Must be safe to call more than once.
    func initialize(consent: AdConsent) async

    /// Consent changed after launch, for example the user revisited the CMP.
    func updateConsent(_ consent: AdConsent)

    /// A banner to place, or nil when none is available.
    ///
    /// Deliberately `AnyView`: the app positions it without knowing what it is.
    func bannerView() -> AnyView?

    /// Preload, so a later show is instant. Failure is not an error.
    func preload(_ format: AdFormat) async

    /// Show an interstitial. Returns false when none was shown, for any reason;
    /// the caller continues regardless. An ad is never worth blocking a user.
    @discardableResult
    func showInterstitial(from presenter: UIViewController?) async -> Bool
}

/// The provider used when the user has paid, when consent forbids ads, or when
/// ads are switched off.
///
/// The paid tier is a provider rather than a branch. That keeps entitlement to a
/// single decision — which provider to build — instead of a `guard
/// !isPremiumUser` in every method, which is what the code did before.
@MainActor
final class NoAdsProvider: AdProvider {
    let name = "none"
    let isAvailable = false

    func initialize(consent: AdConsent) async {}
    func updateConsent(_ consent: AdConsent) {}
    func bannerView() -> AnyView? { nil }
    func preload(_ format: AdFormat) async {}

    @discardableResult
    func showInterstitial(from presenter: UIViewController?) async -> Bool { false }
}

/// Which network to build.
///
/// Swapping networks is a change to this value plus one adapter file. If it ever
/// takes more than that, the abstraction has drifted and should be corrected
/// rather than worked around.
enum AdProviderKind: String {
    case adMob
    case none

    static let `default`: AdProviderKind = .adMob
}

@MainActor
enum AdProviderFactory {
    /// - Parameter serveAds: false yields `NoAdsProvider`. The caller decides
    ///   why — paid, no consent, or switched off — so that reason lives in one
    ///   place rather than being re-derived inside every adapter.
    static func make(kind: AdProviderKind = .default, serveAds: Bool) -> AdProvider {
        guard serveAds else { return NoAdsProvider() }

        switch kind {
        case .adMob: return AdMobProvider()
        case .none: return NoAdsProvider()
        }
    }
}

// MARK: - Presentation

extension UIApplication {
    /// The controller an ad or a consent form should be presented from.
    ///
    /// Walks the presentation stack rather than stopping at the root. Presenting
    /// over a controller that already has a sheet up silently does nothing,
    /// which would mean ads and consent forms failing precisely for users who
    /// are mid-task with a modal open.
    var topMostViewController: UIViewController? {
        let root = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow?
            .rootViewController

        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
