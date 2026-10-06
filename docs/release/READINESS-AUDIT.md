# Release readiness audit — iOS

First inspected 2026-10-05 against `feat/nova64-3d-library` (`619b4c8`).
Updated 2026-10-05 after the monetization rebuild.

The plan this came from states that no source had been inspected. This document
is that inspection. Everything below is evidence-backed with a file and line;
nothing here is assumed from the plan.

**Headline, originally:** the app did not have the free/paid split it is meant to
ship with. Ads were wired to Google's public test account and the "premium" flag
was an unvalidated local boolean.

**Headline now:** the architecture is in place and tested. What remains is
console work — an AdMob account with live ad units, and a product registered in
App Store Connect. No open P0 is a code problem.

---

## Status summary

| # | Issue | Severity | Status |
|---|---|---|---|
| 1 | Bundle identifier was `com.example.*` | P0 | **Fixed** — `studio.seacloud9.maigexr` |
| 2 | Ads on Google's public test account | P0 | **Partly** — structure done, needs the real account |
| 3 | No paid tier | P0 | **Fixed** — StoreKit non-consumable + restore |
| 4 | No privacy manifest | P0 | **Fixed** — `PrivacyInfo.xcprivacy`, needs verifying against an archive |
| 5 | No consent flow | P0 | **Fixed** — UMP + ATT |
| 6 | Ads hardwired to one provider | P1 | **Fixed** — `AdProvider` seam |
| 7 | Ad gate was the only tier difference | P1 | **Fixed** — entitlement is a provider, not a branch |
| 8 | iOS ad code never called | P0 | **Fixed** — banner placed, signals wired |

---

## Corrections to the first version of this audit

Two things in the original were wrong. Recorded because both changed the shape of
the work.

### The iOS ad code was dormant — no ad had ever rendered

The first version implied ads were live on iOS and serving test units. They were
not wired up at all: nothing called `AdManager.initialize()` and `AdBannerView`
was never placed in any view. So the problem was not "fix the ad integration",
it was "build it".

**Android was the opposite — and still is fully wired:** `MainActivity.kt:43`
injects `AdManager`, `MainScreen.kt:224` places `AdBannerView`, and
`SceneScreen.kt:99` fires an interstitial check per scene run. Any statement
about "the app's ads" has to name the platform.

### AdMob comes from SPM; the `Podfile` is dead

The first version said `GoogleUserMessagingPlatform` "is in the `Podfile` but is
never referenced in source", implying a dependency needed adding. In fact:

- There is **no `Podfile.lock`, no `Pods/`, no `.xcworkspace`** — CocoaPods was
  never installed. The `Podfile` pins `Google-Mobile-Ads-SDK ~> 11.0` and
  `UnityAds`, neither of which is built, and a deployment target of 16.0 against
  the project's actual 18.0.
- The real dependency is SPM: `swift-package-manager-google-mobile-ads` **13.0.0**.
- `GoogleUserMessagingPlatform` **3.1.0** was already resolved and already
  linked. Confirmed in the built app:
  `XRAiAssistant.app/Frameworks/UserMessagingPlatform.framework`.

So consent was only ever a code task. **The `Podfile` should be deleted** — it
has misled this audit once already.

---

## Open — needs console access, not code

### Real AdMob account and ad units

`XRAiAssistant/Info.plist` still carries Google's public sample app ID:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-3940256099942544~1458002511</string>
```

`ca-app-pub-3940256099942544` is Google's published sample account, shared by
every tutorial. Shipping it serves test ads, earns nothing, and signals an
unfinished build to review.

The code is ready for the real values. `AdUnits` in `AdMobProvider.swift` reads
release units from `Info.plist` (`GADBannerUnitID`, `GADInterstitialUnitID`),
which are present and empty. Empty is handled rather than crashing: the provider
declines to load and the app serves nothing.

**Still to do:** create the AdMob app, create banner and interstitial units,
replace `GADApplicationIdentifier`, and fill the two unit keys. Debug builds keep
Google's test units deliberately — serving live ads to a development device risks
the account.

**Recommended while doing it:** drive `GADApplicationIdentifier` from a build
setting per configuration, the way Android already does with
`manifestPlaceholders`, so a debug build cannot carry the production ID.

### App Store Connect product

`StoreEntitlement.removeAdsProductID` is `studio.seacloud9.maigexr.removeads`.
A matching **non-consumable** must be created in App Store Connect, with a price.
`maigeXR.storekit` simulates it locally so the flow can be tested first; the
2.99 in that file is a local simulation value, **not** a price decision.

### Not verified at all

Carry these as unknowns: App Store Connect state, whether an App ID exists for
`studio.seacloud9.maigexr`, signing certificate validity, and any current policy
deadline. `DEVELOPMENT_TEAM = T28W526VKC` is set, so a developer account exists,
but nothing about its state has been checked.

The privacy manifest is **derived from reading the repo, not from an instrumented
build**. Confirm it against Xcode's privacy report of a real archive.

---

## What was built

In the dependency order set out in `MONETIZATION.md`.

### 1. Provider seam

`AdProvider.swift` defines the protocol, `NoAdsProvider`, and the factory.
`AdMobProvider.swift` is now the **only** file importing `GoogleMobileAds` —
verified by grep, and the invariant is stated in both files' headers.

`AdManager` no longer imports an ad SDK, and no AdMob type crosses the protocol:
a banner is an `AnyView` the app places.

**Rewarded ads were cut**, per the owner's decision. The old `RewardType` enum
offered premium model access, GLB/FBX/USD export, cloud sync and unlimited
favourites — features that are not built; `AppConfig.cloudSyncEnabled` is
hardcoded `false` and commented "Not yet implemented". Granting a reward for a
non-existent feature is a rejection risk and a false listing claim. The old
`showRewarded` also had a real bug: it returned `earned` immediately after
`present`, before the completion closure could run, so it always reported false.

### 2. StoreKit entitlement

`StoreEntitlement.swift`. One non-consumable. Reads
`Transaction.currentEntitlements`, keeps a `Transaction.updates` listener alive
for the process lifetime so a purchase on another device or a refund both arrive,
skips revoked transactions, and exposes **Restore Purchases** as Apple requires.

The last known state is cached for offline launch but **written on every refresh**
so a revocation clears a stale `true` rather than being believed forever. StoreKit
overrules the cache whenever it answers.

The old `UserDefaults` key `XRAiAssistant_IsPremium` is **gone, not migrated**.
It was a local boolean with no receipt behind it. Nothing is lost: no purchase
ever existed to record, and iOS never rendered an ad for it to hide.

### 3. Consent

`AdConsentStore.swift`. UMP decides whether ads may be requested at all; ATT
decides only whether they are personalised. Declining ATT still serves ads —
contextual ones — and that is asserted in a test.

`NSUserTrackingUsageDescription` was absent and is now in `Info.plist`; without
it the ATT prompt never appears and the IDFA is never available.

Consent resolution runs **after the splash dismisses**, because both the UMP form
and the ATT prompt are system sheets and presenting them over a splash means
presenting them over nothing. A paid user is never shown a consent form at all.

`privacyOptionsRequirementStatus == .required` obliges a **standing** control, not
a one-time prompt. `RemoveAdsSection` shows a "Privacy options" row when UMP
reports it. This is the part most commonly missed.

### 4. Identity

`PRODUCT_BUNDLE_IDENTIFIER` is `studio.seacloud9.maigexr` across all four
configurations; the test target is `studio.seacloud9.maigexr.tests`. Verified in
the built binary: `CFBundleIdentifier = studio.seacloud9.maigexr`.

**This is irreversible after first publish.** It is the app's identity on the
store and it determines keychain access groups and local data continuity.

### 5. Placement and restraint

The banner sits in the main `VStack` above the tab bar, so it takes its own space
rather than covering the editor or the canvas, and renders nothing — leaving no
gap — for a paid user.

Pacing and restraint live in `AdManager`, above the provider, so a network swap
cannot change how often ads appear. `isLoading` and both error surfaces are
forwarded from one place in `ContentView` rather than sprinkled through every
request path.

---

## Evidence

Xcode 26.6 (17F113), iOS SDK 26.5, Swift 6.3.3, Swift 5 language mode,
deployment target iOS 18.0.

- `xcodebuild build`, Debug, iPhone 17 Pro simulator → **BUILD SUCCEEDED**,
  0 errors, 0 warnings in `Monetization/`.
- `xcodebuild test -only-testing:XRAiAssistantTests/AdPacingTests` →
  **TEST SUCCEEDED**, 17 of 17 passed.
- Built bundle contains `PrivacyInfo.xcprivacy`, and AdMob and UMP each ship
  their own.
- Seam verified: `grep -rl "import GoogleMobileAds"` returns exactly
  `AdMobProvider.swift`.

**NOT RUN:** no physical device, no release archive, no Android build, and no
test of a real purchase against App Store Connect. The StoreKit flow has not been
exercised even locally — the config file is attached to the scheme but a purchase
has not been driven through the simulator.

---

## Decide before listing

- `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` — fine for a first
  release; the build number must increase per upload.
- **When an interstitial should appear.** It is currently never triggered: the
  pacing is implemented and tested, but no call site invokes `onSceneRun()`.
  Doing it on the Run Scene tap would cover the scene the user just asked to see.
  This needs a deliberate choice — see `MONETIZATION.md` step 5.
- Banner placement is implemented as described above, but it costs 50pt of canvas
  height on a phone. Worth looking at on a real device before committing to it.
- The ATT usage string and the Settings copy both assert that the free tier is
  fully functional. That must stay true, or both become false claims.
