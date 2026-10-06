import XCTest
import SwiftUI
@testable import XRAiAssistant

/// The point of these is the restraint, not the plumbing.
///
/// An ad shown at the wrong moment is the failure mode that costs reviews: one
/// landing on a user waiting for a slow reasoning model, or covering the error
/// explaining why their generation failed, reads as a broken app rather than as
/// advertising. Those rules are invisible in normal use — they only show up
/// eight minutes and three scenes later — so they are asserted here directly.
///
/// They also guard the shape of the design: a paid user, a user who refused
/// consent, and a user who was never asked must all get the same provider, so
/// entitlement stays one decision instead of a check in every method.
@MainActor
final class AdPacingTests: XCTestCase {

    // MARK: - Doubles

    /// Counts shows and never touches a network.
    private final class FakeProvider: AdProvider {
        let name = "fake"
        var isAvailable = true

        var interstitialsShown = 0
        var bannerRequested = false
        /// Simulates "nothing loaded yet", so the caller's retry can be checked.
        var hasInterstitialReady = true

        func initialize(consent: AdConsent) async {}
        func updateConsent(_ consent: AdConsent) {}

        func bannerView() -> AnyView? {
            bannerRequested = true
            return AnyView(EmptyView())
        }

        func preload(_ format: AdFormat) async {}

        @discardableResult
        func showInterstitial(from presenter: UIViewController?) async -> Bool {
            guard hasInterstitialReady else { return false }
            interstitialsShown += 1
            return true
        }
    }

    private final class FakeEntitlement: EntitlementSource {
        var onEntitlementChange: ((Bool) -> Void)?
        var isEntitled: Bool

        init(isEntitled: Bool) { self.isEntitled = isEntitled }

        /// Mimics a purchase or a refund arriving from StoreKit.
        func change(to entitled: Bool) {
            isEntitled = entitled
            onEntitlementChange?(entitled)
        }
    }

    /// Builds a manager wired to `provider`, with ads on and no cooldown unless
    /// a test asks for one.
    private func makeManager(
        provider: FakeProvider,
        entitlement: EntitlementSource? = nil,
        scenesBeforeInterstitial: Int = 3,
        minimumInterval: TimeInterval = 0,
        adsEnabled: Bool = true
    ) -> AdManager {
        AdManager(
            entitlement: entitlement ?? FakeEntitlement(isEntitled: false),
            adsEnabled: adsEnabled,
            pacing: AdPacing(
                scenesBeforeInterstitial: scenesBeforeInterstitial,
                minimumInterval: minimumInterval
            ),
            buildProvider: { serveAds in serveAds ? provider as AdProvider : NoAdsProvider() }
        )
    }

    // MARK: - Scene counting

    func testNoInterstitialBeforeTheSceneThreshold() async {
        let provider = FakeProvider()
        let ads = makeManager(provider: provider, scenesBeforeInterstitial: 3)
        await ads.start(consent: .personalised)

        await ads.onSceneRun()
        await ads.onSceneRun()

        XCTAssertEqual(provider.interstitialsShown, 0, "two scenes should not reach a threshold of three")
    }

    func testInterstitialAtTheSceneThreshold() async {
        let provider = FakeProvider()
        let ads = makeManager(provider: provider, scenesBeforeInterstitial: 3)
        await ads.start(consent: .personalised)

        for _ in 0..<3 { await ads.onSceneRun() }

        XCTAssertEqual(provider.interstitialsShown, 1)
    }

    func testCounterResetsAfterAnInterstitialSoAdsDoNotRepeatEveryRun() async {
        let provider = FakeProvider()
        let ads = makeManager(provider: provider, scenesBeforeInterstitial: 2)
        await ads.start(consent: .personalised)

        for _ in 0..<4 { await ads.onSceneRun() }

        XCTAssertEqual(provider.interstitialsShown, 2, "four scenes at a threshold of two is two ads, not three")
    }

    /// If the network had nothing ready, the user has not seen an ad, so the
    /// count must stand rather than restarting a whole cycle.
    func testCounterSurvivesAProviderWithNothingToShow() async {
        let provider = FakeProvider()
        provider.hasInterstitialReady = false
        let ads = makeManager(provider: provider, scenesBeforeInterstitial: 2)
        await ads.start(consent: .personalised)

        await ads.onSceneRun()
        await ads.onSceneRun()
        XCTAssertEqual(provider.interstitialsShown, 0)

        provider.hasInterstitialReady = true
        await ads.onSceneRun()

        XCTAssertEqual(provider.interstitialsShown, 1, "the next run should retry, not wait another full cycle")
    }

    // MARK: - Cooldown

    func testCooldownBlocksASecondInterstitial() async {
        let provider = FakeProvider()
        let ads = makeManager(
            provider: provider,
            scenesBeforeInterstitial: 1,
            minimumInterval: 600
        )
        await ads.start(consent: .personalised)

        await ads.onSceneRun()
        XCTAssertEqual(provider.interstitialsShown, 1)

        for _ in 0..<5 { await ads.onSceneRun() }

        XCTAssertEqual(provider.interstitialsShown, 1, "five more scenes inside a ten-minute cooldown must still be one ad")
    }

    // MARK: - Restraint

    func testNoInterstitialWhileAGenerationIsInFlight() async {
        let provider = FakeProvider()
        let ads = makeManager(provider: provider, scenesBeforeInterstitial: 1)
        await ads.start(consent: .personalised)

        ads.generationBegan()
        for _ in 0..<3 { await ads.onSceneRun() }

        XCTAssertEqual(provider.interstitialsShown, 0, "an ad must never land on a user waiting for a model")
    }

    func testInterstitialResumesOnceTheGenerationFinishes() async {
        let provider = FakeProvider()
        let ads = makeManager(provider: provider, scenesBeforeInterstitial: 1)
        await ads.start(consent: .personalised)

        ads.generationBegan()
        await ads.onSceneRun()
        XCTAssertEqual(provider.interstitialsShown, 0)

        ads.generationEnded()
        await ads.onSceneRun()

        XCTAssertEqual(provider.interstitialsShown, 1)
    }

    /// The reason the count is a count and not a flag.
    func testOverlappingGenerationsStayBlockedUntilTheLastOneEnds() async {
        let provider = FakeProvider()
        let ads = makeManager(provider: provider, scenesBeforeInterstitial: 1)
        await ads.start(consent: .personalised)

        ads.generationBegan()
        ads.generationBegan()
        ads.generationEnded()

        await ads.onSceneRun()
        XCTAssertEqual(provider.interstitialsShown, 0, "one of two generations finishing must not re-open the door")

        ads.generationEnded()
        await ads.onSceneRun()
        XCTAssertEqual(provider.interstitialsShown, 1)
    }

    func testNoInterstitialOverAVisibleError() async {
        let provider = FakeProvider()
        let ads = makeManager(provider: provider, scenesBeforeInterstitial: 1)
        await ads.start(consent: .personalised)

        ads.setErrorVisible(true)
        for _ in 0..<3 { await ads.onSceneRun() }
        XCTAssertEqual(provider.interstitialsShown, 0, "an ad must never cover the explanation of a failure")

        ads.setErrorVisible(false)
        await ads.onSceneRun()
        XCTAssertEqual(provider.interstitialsShown, 1)
    }

    /// `generationEnded` is called from error paths too, so it must not be able
    /// to drive the count below zero and leave ads permanently suppressed.
    func testUnbalancedGenerationEndedDoesNotSuppressAdsForever() async {
        let provider = FakeProvider()
        let ads = makeManager(provider: provider, scenesBeforeInterstitial: 1)
        await ads.start(consent: .personalised)

        ads.generationEnded()
        ads.generationEnded()
        ads.generationBegan()
        ads.generationEnded()

        await ads.onSceneRun()

        XCTAssertEqual(provider.interstitialsShown, 1)
    }

    // MARK: - Who gets ads at all

    func testPaidUserGetsNoProviderAndNoBanner() async {
        let provider = FakeProvider()
        let ads = makeManager(
            provider: provider,
            entitlement: FakeEntitlement(isEntitled: true),
            scenesBeforeInterstitial: 1
        )
        await ads.start(consent: .personalised)

        for _ in 0..<3 { await ads.onSceneRun() }

        XCTAssertTrue(ads.isEntitled)
        XCTAssertFalse(ads.adsAreServing)
        XCTAssertNil(ads.bannerView(), "a paid user must not be offered a banner to place")
        XCTAssertEqual(provider.interstitialsShown, 0)
        XCTAssertFalse(provider.bannerRequested, "the ad network should not even be asked")
    }

    func testRefusedConsentServesNothing() async {
        let provider = FakeProvider()
        let ads = makeManager(provider: provider, scenesBeforeInterstitial: 1)

        await ads.start(consent: .denied)

        await ads.onSceneRun()
        XCTAssertFalse(ads.adsAreServing)
        XCTAssertNil(ads.bannerView())
        XCTAssertEqual(provider.interstitialsShown, 0)
    }

    /// Not having asked yet is as blocking as having been refused. This is what
    /// stops an ad loading before the consent form has been answered.
    func testUnresolvedConsentServesNothing() async {
        let provider = FakeProvider()
        let ads = makeManager(provider: provider, scenesBeforeInterstitial: 1)

        await ads.start(consent: .unknown)

        await ads.onSceneRun()
        XCTAssertFalse(ads.adsAreServing)
        XCTAssertEqual(provider.interstitialsShown, 0)
    }

    func testNonPersonalisedConsentStillServesAds() async {
        let provider = FakeProvider()
        let ads = makeManager(provider: provider, scenesBeforeInterstitial: 1)

        await ads.start(consent: .nonPersonalised)
        await ads.onSceneRun()

        XCTAssertTrue(ads.adsAreServing, "declining tracking reduces personalisation; it does not turn ads off")
        XCTAssertEqual(provider.interstitialsShown, 1)
    }

    func testMasterSwitchOffServesNothing() async {
        let provider = FakeProvider()
        let ads = makeManager(provider: provider, scenesBeforeInterstitial: 1, adsEnabled: false)

        await ads.start(consent: .personalised)
        await ads.onSceneRun()

        XCTAssertFalse(ads.adsAreServing)
        XCTAssertEqual(provider.interstitialsShown, 0)
    }

    // MARK: - Entitlement changes

    func testBuyingRemovesAdsWithoutARelaunch() async {
        let provider = FakeProvider()
        let entitlement = FakeEntitlement(isEntitled: false)
        let ads = makeManager(
            provider: provider,
            entitlement: entitlement,
            scenesBeforeInterstitial: 1
        )
        await ads.start(consent: .personalised)
        XCTAssertTrue(ads.adsAreServing)

        entitlement.change(to: true)
        // The rebuild is asynchronous; let it land.
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(ads.isEntitled)
        XCTAssertFalse(ads.adsAreServing)
        XCTAssertNil(ads.bannerView())
    }

    /// A revoked or refunded purchase has to put ads back, or the entitlement is
    /// one-way and a refund costs the revenue twice.
    func testLosingEntitlementRestoresAds() async {
        let provider = FakeProvider()
        let entitlement = FakeEntitlement(isEntitled: true)
        let ads = makeManager(
            provider: provider,
            entitlement: entitlement,
            scenesBeforeInterstitial: 1
        )
        await ads.start(consent: .personalised)
        XCTAssertFalse(ads.adsAreServing)

        entitlement.change(to: false)
        await Task.yield()
        await Task.yield()

        XCTAssertFalse(ads.isEntitled)
        XCTAssertTrue(ads.adsAreServing)
        XCTAssertNotNil(ads.bannerView())
    }
}
