//
//  AppConfig.swift
//  m{ai}geXR
//
//  Created: 2026-02-08
//  Purpose: Centralized app configuration with environment-based flags
//

import Foundation

/// Global app configuration
enum AppConfig {

    // MARK: - Monetization Settings

    /// Master switch to enable/disable all ads in the app
    /// Set to `false` during development to disable all ads
    /// Set to `true` in production to enable ads
    static let adsEnabled: Bool = {
        #if DEBUG
        // Read from environment or use default
        return ProcessInfo.processInfo.environment["ENABLE_ADS"] == "true"
        #else
        // Always enabled in release builds
        return true
        #endif
    }()

    /// Force premium mode (disables ads regardless of subscription status)
    /// Useful for testing premium features without purchasing
    static let forcePremiumMode: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["FORCE_PREMIUM"] == "true"
        #else
        return false
        #endif
    }()

    /// Show debug logs for ad events
    static let showAdDebugLogs: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["AD_DEBUG_LOGS"] != "false"
        #else
        return false
        #endif
    }()

    // MARK: - Ad Frequency Settings (Development Override)

    /// Minimum seconds between interstitial ads (default: 480 = 8 minutes)
    static let interstitialMinInterval: TimeInterval = {
        #if DEBUG
        if let envValue = ProcessInfo.processInfo.environment["INTERSTITIAL_INTERVAL"],
           let interval = TimeInterval(envValue) {
            return interval
        }
        return 30 // Shorter interval for testing (30 seconds)
        #else
        return 480 // 8 minutes in production
        #endif
    }()

    /// Number of scene runs before showing interstitial ad (default: 3)
    static let scenesBeforeInterstitial: Int = {
        #if DEBUG
        if let envValue = ProcessInfo.processInfo.environment["SCENES_BEFORE_AD"],
           let count = Int(envValue) {
            return count
        }
        return 1 // Show after 1 scene in development
        #else
        return 3 // Show after 3 scenes in production
        #endif
    }()

    // MARK: - API Keys (Environment Override)

    /// AdMob App ID (can be overridden via environment)
    static let admobAppID: String = {
        if let envID = ProcessInfo.processInfo.environment["ADMOB_APP_ID"] {
            return envID
        }
        return "ca-app-pub-3940256099942544~1458002511" // Test ID
    }()

    /// Unity Ads Game ID (can be overridden via environment)
    static let unityGameID: String = {
        if let envID = ProcessInfo.processInfo.environment["UNITY_GAME_ID"] {
            return envID
        }
        return "YOUR_UNITY_GAME_ID_HERE"
    }()

    // MARK: - Feature Flags

    /// Enable premium subscription features
    static let premiumSubscriptionEnabled: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["ENABLE_SUBSCRIPTIONS"] != "false"
        #else
        return true
        #endif
    }()

    /// Enable cloud sync feature
    static let cloudSyncEnabled: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["ENABLE_CLOUD_SYNC"] == "true"
        #else
        return false // Not yet implemented
        #endif
    }()

    // MARK: - Debug Helpers

    /// Print all configuration on app launch
    static func printConfiguration() {
        guard showAdDebugLogs else { return }

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📋 m{ai}geXR Configuration")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎯 Ads Enabled: \(adsEnabled)")
        print("💎 Force Premium: \(forcePremiumMode)")
        print("📊 Ad Debug Logs: \(showAdDebugLogs)")
        print("⏱️ Interstitial Interval: \(interstitialMinInterval)s")
        print("🎮 Scenes Before Ad: \(scenesBeforeInterstitial)")
        print("🔑 AdMob App ID: \(admobAppID)")
        print("🎮 Unity Game ID: \(unityGameID)")
        print("💳 Subscriptions: \(premiumSubscriptionEnabled)")
        print("☁️ Cloud Sync: \(cloudSyncEnabled)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}
