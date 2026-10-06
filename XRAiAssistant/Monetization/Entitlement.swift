//
//  Entitlement.swift
//  m{ai}geXR
//
//  Where "has the user paid?" comes from.
//
//  Kept behind a protocol so AdManager does not import StoreKit and can be
//  tested without it. StoreKit implements this next; see
//  docs/release/MONETIZATION.md step 2.
//

import Foundation

/// The source of truth for the one purchase this app sells: removing ads.
@MainActor
protocol EntitlementSource: AnyObject {
    /// True when the user has paid to remove ads.
    var isEntitled: Bool { get }

    /// Called whenever the answer changes — a purchase here, a purchase on
    /// another device, a refund, a restore.
    var onEntitlementChange: ((Bool) -> Void)? { get set }
}

/// A stand-in for tests and SwiftUI previews, where StoreKit is unavailable or
/// would prompt. The app itself uses `StoreEntitlement`.
///
/// Reports **not entitled** unless forced, so a test gets the free tier by
/// default and has to opt into the paid one.
///
/// It deliberately does not read the old `XRAiAssistant_IsPremium` UserDefaults
/// key that `AdManager` used to consult. That key was a plain local boolean with
/// no receipt behind it — trivially settable, not an entitlement, and flagged
/// P0 in docs/release/READINESS-AUDIT.md. Nothing is lost by dropping it: no
/// purchase ever existed to record, and iOS never rendered an ad for it to hide.
///
/// `AppConfig.forcePremiumMode` is still honoured so the paid path can be
/// exercised in debug builds. It compiles to `false` in release.
@MainActor
final class UnpurchasedEntitlement: EntitlementSource {
    var onEntitlementChange: ((Bool) -> Void)?

    var isEntitled: Bool { AppConfig.forcePremiumMode }
}
