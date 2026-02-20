//
//  AdManager.swift
//  m{ai}geXR
//
//  Created: 2026-02-08
//  Purpose: Manages ad display (AdMob only) and premium subscription status
//  Updated: 2026-02-08 - Removed Unity Ads, using AdMob for all ad types
//

import Foundation
import SwiftUI
import GoogleMobileAds
// Unity Ads removed - AdMob supports all ad types (banner, interstitial, rewarded)

class AdManager: NSObject, ObservableObject {
    static let shared = AdManager()

    // MARK: - Published Properties

    @Published var bannerAdView: BannerView?
    @Published var isPremiumUser = false

    // MARK: - Private Properties

    private var interstitialAd: InterstitialAd?
    private var rewardedAd: RewardedAd?

    // Ad frequency tracking
    private var lastInterstitialShown: Date?
    private var scenesRunSinceLastAd = 0
    private let minInterstitialInterval: TimeInterval = AppConfig.interstitialMinInterval
    private let scenesBeforeInterstitial = AppConfig.scenesBeforeInterstitial

    // Ad Unit IDs - Using AdMob test IDs (replace with your actual IDs)
    private let bannerAdUnitID = "ca-app-pub-3940256099942544/2934735716" // Test ID
    private let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910" // Test ID
    private let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313" // Test ID - AdMob rewarded

    // MARK: - Initialization

    private override init() {
        super.init()
        checkPremiumStatus()

        // Print configuration on initialization
        if AppConfig.showAdDebugLogs {
            AppConfig.printConfiguration()
        }
    }

    // MARK: - Public Methods

    /// Initialize both AdMob and Unity Ads
    func initialize() {
        logDebug("🎯 AdManager: Initializing...")

        // Check environment flag - ads globally disabled
        guard AppConfig.adsEnabled else {
            logDebug("🚫 Ads globally disabled via AppConfig.adsEnabled")
            return
        }

        // Check force premium mode
        if AppConfig.forcePremiumMode {
            logDebug("💎 Force premium mode enabled - ads disabled")
            isPremiumUser = true
            return
        }

        // Check if premium user (skip ads if true)
        if isPremiumUser {
            logDebug("✅ Premium user detected - ads disabled")
            return
        }

        // Initialize AdMob (handles all ad types: banner, interstitial, rewarded)
        initializeAdMob()

        // Load initial rewarded ad
        loadRewardedAd()
    }

    /// Log debug messages only when debug logs are enabled
    private func logDebug(_ message: String) {
        if AppConfig.showAdDebugLogs {
            print(message)
        }
    }

    // MARK: - Banner Ads (AdMob)

    /// Load and return a banner ad view
    func loadBannerAd(rootViewController: UIViewController) -> BannerView {
        logDebug("📱 Loading AdMob banner ad...")

        let bannerView = BannerView(adSize: adSizeFor(cgSize: CGSize(width: 320, height: 50)))
        bannerView.adUnitID = bannerAdUnitID
        bannerView.rootViewController = rootViewController
        bannerView.delegate = self
        bannerView.load(Request())

        self.bannerAdView = bannerView
        return bannerView
    }

    // MARK: - Interstitial Ads (AdMob)

    /// Preload an interstitial ad
    func loadInterstitialAd() {
        guard !isPremiumUser else { return }

        logDebug("📺 Loading AdMob interstitial ad...")

        let request = Request()
        InterstitialAd.load(
            with: interstitialAdUnitID,
            request: request
        ) { [weak self] ad, error in
            if let error = error {
                self?.logDebug("❌ Failed to load interstitial ad: \(error.localizedDescription)")
                return
            }

            self?.interstitialAd = ad
            self?.interstitialAd?.fullScreenContentDelegate = self
            self?.logDebug("✅ Interstitial ad loaded successfully")
        }
    }

    /// Show interstitial ad if conditions are met
    func showInterstitialAd(from viewController: UIViewController, onAdClosed: @escaping () -> Void) {
        guard !isPremiumUser else {
            print("⏭️ Premium user - skipping interstitial ad")
            onAdClosed()
            return
        }

        // Check frequency cap
        if let lastShown = lastInterstitialShown,
           Date().timeIntervalSince(lastShown) < minInterstitialInterval {
            let timeRemaining = minInterstitialInterval - Date().timeIntervalSince(lastShown)
            print("⏱️ Too soon to show interstitial ad (wait \(Int(timeRemaining))s)")
            onAdClosed()
            return
        }

        // Show ad if loaded
        if let ad = interstitialAd {
            ad.present(from: viewController)
            lastInterstitialShown = Date()
            print("✅ Showing interstitial ad")

            // Store completion handler
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onAdClosed()
            }

            // Preload next ad
            loadInterstitialAd()
        } else {
            print("⚠️ Interstitial ad not ready")
            onAdClosed()
            loadInterstitialAd() // Try to load for next time
        }
    }

    // MARK: - Rewarded Video Ads (AdMob)

    /// Load a rewarded ad
    func loadRewardedAd() {
        guard !isPremiumUser else { return }

        logDebug("🎬 Loading AdMob rewarded ad...")

        let request = Request()
        RewardedAd.load(
            with: rewardedAdUnitID,
            request: request
        ) { [weak self] ad, error in
            if let error = error {
                self?.logDebug("❌ Failed to load rewarded ad: \(error.localizedDescription)")
                return
            }

            self?.rewardedAd = ad
            self?.rewardedAd?.fullScreenContentDelegate = self
            self?.logDebug("✅ Rewarded ad loaded successfully")
        }
    }

    /// Show rewarded video ad (AdMob)
    func showRewardedAd(from viewController: UIViewController, rewardType: RewardType, onRewardEarned: @escaping (Bool) -> Void) {
        guard !isPremiumUser else {
            logDebug("⏭️ Premium user - granting reward directly")
            onRewardEarned(true)
            return
        }

        logDebug("🎬 Attempting to show AdMob rewarded ad...")

        if let ad = rewardedAd {
            ad.present(from: viewController, userDidEarnRewardHandler: {
                let reward = ad.adReward
                self.logDebug("✅ User earned reward: \(reward.amount) \(reward.type)")
                onRewardEarned(true)

                // Preload next rewarded ad
                self.loadRewardedAd()
            })
        } else {
            logDebug("⚠️ AdMob rewarded ad not ready")
            onRewardEarned(false)
            loadRewardedAd() // Try to load for next time
        }
    }

    // MARK: - Ad Frequency Logic

    /// Call this when a scene is run to track ad frequency
    func onSceneRun() {
        guard !isPremiumUser else { return }

        scenesRunSinceLastAd += 1
        print("📊 Scenes run since last ad: \(scenesRunSinceLastAd)/\(scenesBeforeInterstitial)")

        // Note: The actual showing of the ad should be triggered from the view controller
        // This just tracks the count
    }

    /// Check if it's time to show an interstitial ad
    func shouldShowInterstitial() -> Bool {
        guard !isPremiumUser else { return false }

        let frequencyCheck = scenesRunSinceLastAd >= scenesBeforeInterstitial
        let timeCheck = lastInterstitialShown == nil ||
            Date().timeIntervalSince(lastInterstitialShown!) >= minInterstitialInterval

        return frequencyCheck && timeCheck
    }

    /// Reset scene counter after showing ad
    func resetSceneCounter() {
        scenesRunSinceLastAd = 0
    }

    // MARK: - Premium Status

    private func checkPremiumStatus() {
        // Load premium status from UserDefaults
        isPremiumUser = UserDefaults.standard.bool(forKey: "XRAiAssistant_IsPremium")
        print("💎 Premium status: \(isPremiumUser ? "ACTIVE" : "FREE")")
    }

    func setPremiumStatus(_ isPremium: Bool) {
        isPremiumUser = isPremium
        UserDefaults.standard.set(isPremium, forKey: "XRAiAssistant_IsPremium")

        if isPremium {
            print("💎 Premium activated - removing ads")
            // Remove banner ad
            bannerAdView?.removeFromSuperview()
            bannerAdView = nil
            // Clear loaded ads
            interstitialAd = nil
            rewardedAd = nil
        } else {
            print("🆓 Switched to free tier - ads enabled")
        }
    }

    // MARK: - Private Initialization Helpers

    private func initializeAdMob() {
        MobileAds.shared.start { status in
            self.logDebug("✅ AdMob initialized")
            self.logDebug("📊 AdMob adapter statuses:")
            for (key, value) in status.adapterStatusesByClassName {
                let state = value.state.rawValue
                self.logDebug("   • \(key): \(state == 1 ? "Ready" : "Not Ready")")
            }

            // Preload first interstitial ad
            self.loadInterstitialAd()
            // Preload first rewarded ad
            self.loadRewardedAd()
        }
    }
}

// MARK: - AdMob Banner Delegate

extension AdManager: BannerViewDelegate {
    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        logDebug("✅ Banner ad received")
    }

    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        logDebug("❌ Banner ad failed: \(error.localizedDescription)")
    }

    func bannerViewDidRecordClick(_ bannerView: BannerView) {
        logDebug("👆 Banner ad clicked")
    }
}

// MARK: - AdMob Interstitial Delegate

extension AdManager: FullScreenContentDelegate {
    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        logDebug("📊 Interstitial ad impression recorded")
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        logDebug("👆 Interstitial ad clicked")
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        logDebug("❌ Interstitial ad failed to present: \(error.localizedDescription)")
    }

    func adWillDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        logDebug("⏹️ Interstitial ad will dismiss")
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        logDebug("✅ Interstitial ad dismissed")
        // Ad is dismissed, completion handler already called
    }
}

// MARK: - Reward Types

enum RewardType {
    case premiumModelAccess  // Unlock 1 premium AI model usage
    case advancedExport      // Unlock advanced export format
    case cloudSync           // Unlock cloud sync feature
    case unlimitedFavorites  // Unlock unlimited favorites temporarily

    var displayName: String {
        switch self {
        case .premiumModelAccess: return "Premium AI Model Access"
        case .advancedExport: return "Advanced Export"
        case .cloudSync: return "Cloud Sync"
        case .unlimitedFavorites: return "Unlimited Favorites"
        }
    }

    var description: String {
        switch self {
        case .premiumModelAccess:
            return "Unlock GPT-5.2, Claude Opus 4, or Gemini 2.5 Pro for one use"
        case .advancedExport:
            return "Export your scene to GLB, FBX, or USD format"
        case .cloudSync:
            return "Sync your conversations across all devices"
        case .unlimitedFavorites:
            return "Save unlimited favorite scenes for 24 hours"
        }
    }
}
