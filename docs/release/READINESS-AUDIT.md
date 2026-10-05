# Release readiness audit — iOS

Inspected: 2026-10-05, against `feat/nova64-3d-library`.

The plan this came from states that no source had been inspected. This document
is that inspection. Everything below is evidence-backed with a file and line;
nothing here is assumed from the plan.

**Headline:** the app does not currently have the free/paid split it is meant to
ship with. Ads are wired to Google's public test account, and the "premium" flag
is an unvalidated local boolean that anyone can set. Both are P0.

---

## P0 — blocks submission

### 1. Bundle identifier is a placeholder

`XRAiAssistant.xcodeproj/project.pbxproj:394`

```
PRODUCT_BUNDLE_IDENTIFIER = com.example.XRAiAssistant;
```

`com.example.*` is a template value and cannot be registered to a real team. It
also carries the retired product name.

The team ID is already set (`DEVELOPMENT_TEAM = T28W526VKC`), so an Apple
Developer account exists — the identifier simply needs to be chosen, registered
in the portal, and an App ID created before anything can be uploaded.

**Note this is irreversible.** The bundle ID is the app's identity on the store.
It cannot be changed after first publish, and it determines keychain access
groups and local data continuity. Choose it deliberately.

### 2. Ads run on Google's public test account

`XRAiAssistant/Info.plist`

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-3940256099942544~1458002511</string>
```

`XRAiAssistant/Monetization/AdManager.swift:34-36`

```swift
private let bannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"      // Test ID
private let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910" // Test ID
private let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"     // Test ID
```

`ca-app-pub-3940256099942544` is Google's published sample account, shared by
every tutorial. Shipping it serves test ads, earns nothing, and signals an
unfinished build to review.

### 3. There is no paid tier

`XRAiAssistant/Monetization/AdManager.swift:248-250`

```swift
private func checkPremiumStatus() {
    isPremiumUser = UserDefaults.standard.bool(forKey: "XRAiAssistant_IsPremium")
}
```

No StoreKit anywhere in the target — `grep -rl StoreKit` returns nothing. So:

- There is no product to buy, so the paid tier does not exist as a product.
- `isPremiumUser` is a plain `UserDefaults` boolean with no receipt behind it.
  It is local, unvalidated, and trivially settable, so it is not an entitlement.
- There is no restore path, which Apple requires for non-consumable purchases.

Every ad gate in the file reads this flag (`guard !isPremiumUser`), so the
free/paid split is currently decorative.

### 4. No privacy manifest

No `PrivacyInfo.xcprivacy` exists in the target. Apple requires a privacy
manifest describing collected data categories and required-reason API use, and
AdMob is among the SDKs expected to carry one. Confirm the current requirement
at submission time rather than from this document.

### 5. No consent flow for advertising

`GoogleUserMessagingPlatform` is in the `Podfile` but is never referenced in
source. `ATTrackingManager` is never called, and `NSUserTrackingUsageDescription`
is absent from `Info.plist`.

An ad-supported app generally needs:

- **ATT** before any tracking identifier is used, with a usage-description
  string, or the IDFA is simply unavailable.
- **A consent platform** for users in the EEA and UK before personalised ads.

Serving personalised ads without these is both a policy and a legal exposure.

---

## P1 — fix before review

### 6. Ads are hardwired to one provider

`XRAiAssistant/Monetization/AdManager.swift:12` imports `GoogleMobileAds`
directly, and the class exposes AdMob types in its own API
(`@Published var bannerAdView: BannerView?`). Swapping or adding a network means
editing the manager and everything that touches it.

This is addressed in `MONETIZATION.md`; it is listed here because it also
affects review risk. A network switch after approval should not require
re-architecting the app.

### 7. The ad gate is the only thing separating the tiers

Because `isPremiumUser` is a local boolean, the paid tier currently means "ads
hidden on this device". Entitlement has to come from StoreKit and be restorable
across the user's devices, or the purchase is not what the store listing claims.

---

## Not blockers, but decide before listing

- `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` — fine for a first
  release; the build number must increase per upload.
- The app ships `AdBannerView` and rewarded-ad support. Decide whether rewarded
  ads are in v1 scope; they carry their own review expectations.
- `AppConfig` already gates ads behind `adsEnabled` and tunes interstitial
  frequency. That is a good base for the pacing rules in `MONETIZATION.md`.

---

## What was verified and what was not

Verified by reading the repository at the stated commit: identifiers, ad unit
IDs, absence of StoreKit, absence of a privacy manifest, absence of consent
code, and the ad gating logic.

**Not verified:** App Store Connect state, whether an App ID exists, whether the
AdMob account has live ad units, signing certificate validity, and any current
policy deadline. Those need console access and a check against the live policy
pages at submission time.
