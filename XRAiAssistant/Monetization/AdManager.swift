//
//  AdManager.swift
//  m{ai}geXR
//
//  Decides whether an ad may appear, and how often. Not how to fetch one —
//  that is the provider's job, behind AdProvider.
//
//  This file must not import an ad SDK. AdMobProvider.swift is the only place
//  GoogleMobileAds appears; if that stops being true the abstraction has leaked.
//  See docs/release/MONETIZATION.md.
//

import SwiftUI

/// How often an interstitial may appear.
///
/// Data rather than scattered `AppConfig` reads, so the rules can be stated and
/// tested directly instead of only being observable by waiting eight minutes.
struct AdPacing {
    /// Scene runs that must happen before an interstitial is considered.
    var scenesBeforeInterstitial: Int

    /// Minimum time between two interstitials.
    var minimumInterval: TimeInterval

    static var fromAppConfig: AdPacing {
        AdPacing(
            scenesBeforeInterstitial: AppConfig.scenesBeforeInterstitial,
            minimumInterval: AppConfig.interstitialMinInterval
        )
    }
}

/// Builds a provider given whether ads should be served at all.
typealias AdProviderBuilder = @MainActor (Bool) -> AdProvider

/// Owns the ad provider and the product rules about when ads may show.
///
/// Three things live here rather than in a provider, because they must survive a
/// network swap unchanged:
///
/// 1. **Which provider to build.** Paid, consent-denied and ads-disabled all
///    collapse to `NoAdsProvider`, so there is exactly one decision about
///    entitlement in the app instead of a `guard !isPremiumUser` in every method.
/// 2. **Pacing.** Scene counts and cooldowns.
/// 3. **Restraint.** Never over a generation in flight, never over an error.
@MainActor
final class AdManager: ObservableObject {
    static let shared = AdManager(entitlement: StoreEntitlement.shared)

    // MARK: - Published state

    /// True when the user has paid to remove ads. Drives the Settings UI.
    @Published private(set) var isEntitled: Bool

    /// True when a provider is live and may serve. A banner placement uses this
    /// to decide whether to reserve space at all, so the layout does not leave
    /// a 50pt hole for a paid user.
    @Published private(set) var adsAreServing = false

    // MARK: - Collaborators

    private var provider: AdProvider = NoAdsProvider()
    private var entitlement: EntitlementSource
    private var consent: AdConsent = .unknown

    private let adsEnabled: Bool
    private let pacing: AdPacing
    private let buildProvider: AdProviderBuilder

    // MARK: - Pacing

    private var lastInterstitialAt: Date?
    private var scenesSinceInterstitial = 0

    /// Counted rather than a flag: two overlapping generations must not let the
    /// first one to finish re-open the door while the second is still running.
    private var generationsInFlight = 0
    private var isShowingError = false

    // MARK: - Init

    /// - Parameters:
    ///   - entitlement: nil builds the default source. It cannot be a default
    ///     argument: those are evaluated at the call site in a nonisolated
    ///     context, which cannot reach a `@MainActor` initializer.
    ///   - buildProvider: nil uses `AdProviderFactory`. Injectable so the pacing
    ///     rules can be tested against a provider that does not talk to a network.
    init(
        entitlement: EntitlementSource? = nil,
        providerKind: AdProviderKind = .default,
        adsEnabled: Bool = AppConfig.adsEnabled,
        pacing: AdPacing = .fromAppConfig,
        buildProvider: AdProviderBuilder? = nil
    ) {
        let source = entitlement ?? UnpurchasedEntitlement()
        self.entitlement = source
        self.adsEnabled = adsEnabled
        self.pacing = pacing
        self.buildProvider = buildProvider
            ?? { serveAds in AdProviderFactory.make(kind: providerKind, serveAds: serveAds) }
        self.isEntitled = source.isEntitled

        self.entitlement.onEntitlementChange = { [weak self] entitled in
            self?.entitlementChanged(to: entitled)
        }

        if AppConfig.showAdDebugLogs {
            AppConfig.printConfiguration()
        }
    }

    // MARK: - Lifecycle

    /// Start ads once consent has been resolved. Safe to call more than once.
    ///
    /// Nothing loads before this, and passing `.unknown` keeps it that way: the
    /// consent decision gates the first request, not the first impression.
    func start(consent: AdConsent) async {
        self.consent = consent
        await rebuildProvider()
    }

    /// The user revisited the consent form, or ATT was answered.
    func updateConsent(_ consent: AdConsent) async {
        guard consent != self.consent else { return }
        self.consent = consent
        await rebuildProvider()
    }

    private func rebuildProvider() async {
        // The single decision about entitlement in the whole app.
        let serveAds = adsEnabled && !isEntitled && consent.allowsAds

        provider = buildProvider(serveAds)
        await provider.initialize(consent: consent)

        adsAreServing = provider.isAvailable
        log("provider=\(provider.name) serving=\(adsAreServing) consent=\(consent)")

        if adsAreServing {
            await provider.preload(.interstitial)
        }
    }

    private func entitlementChanged(to entitled: Bool) {
        guard entitled != isEntitled else { return }

        isEntitled = entitled
        log(entitled ? "entitled — ads off" : "entitlement lost — ads on")
        Task { await rebuildProvider() }
    }

    // MARK: - Banner

    /// The banner to place, or nil when there is none.
    func bannerView() -> AnyView? {
        provider.bannerView()
    }

    // MARK: - Restraint

    /// Call when a generation starts. An interstitial landing on someone waiting
    /// on a slow reasoning model reads as a broken app, not as an ad.
    func generationBegan() {
        generationsInFlight += 1
    }

    /// Call when a generation finishes, fails, or is cancelled.
    func generationEnded() {
        generationsInFlight = max(0, generationsInFlight - 1)
    }

    /// Call when an error becomes visible or is dismissed. An ad must never
    /// cover the explanation of what just went wrong.
    func setErrorVisible(_ visible: Bool) {
        isShowingError = visible
    }

    // MARK: - Interstitials

    /// Count a completed scene run, and show an interstitial if every pacing
    /// rule allows it.
    ///
    /// - Returns: true only when an ad was actually shown.
    @discardableResult
    func onSceneRun() async -> Bool {
        guard adsAreServing else { return false }

        scenesSinceInterstitial += 1
        guard isInterstitialDue else {
            log("scene \(scenesSinceInterstitial)/\(pacing.scenesBeforeInterstitial)")
            return false
        }

        let shown = await provider.showInterstitial(from: UIApplication.shared.topMostViewController)
        if shown {
            lastInterstitialAt = Date()
            scenesSinceInterstitial = 0
            log("interstitial shown")
        } else {
            // Not ready, or nothing to serve. The counter deliberately stays up
            // so the next run tries again instead of waiting another full cycle.
            log("interstitial due but none available")
        }
        return shown
    }

    /// Every rule that has to hold before an interstitial may appear.
    private var isInterstitialDue: Bool {
        guard generationsInFlight == 0 else { return false }
        guard !isShowingError else { return false }
        guard scenesSinceInterstitial >= pacing.scenesBeforeInterstitial else { return false }

        if let last = lastInterstitialAt,
           Date().timeIntervalSince(last) < pacing.minimumInterval {
            return false
        }
        return true
    }

    // MARK: - Internals

    private func log(_ message: String) {
        if AppConfig.showAdDebugLogs { print("🎯 Ads: \(message)") }
    }
}
