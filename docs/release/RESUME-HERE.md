# Resume here — store-readiness work in progress

Updated 2026-10-05. A working note, not a deliverable: current state, what is
decided, and the next action. `READINESS-AUDIT.md` is the evidence; this is the
pointer.

---

## State

**iOS monetization is code-complete, tested and committed.** Steps 1–5 of
`MONETIZATION.md` are done and the interstitial trigger is wired. What is left on
iOS is console work only. **Android is in progress.**

Committed on `feat/nova64-3d-library`:

```
new:  XRAiAssistant/Monetization/AdProvider.swift        the seam
new:  XRAiAssistant/Monetization/AdMobProvider.swift     the only GoogleMobileAds importer
new:  XRAiAssistant/Monetization/Entitlement.swift       EntitlementSource + test double
new:  XRAiAssistant/Monetization/StoreEntitlement.swift  StoreKit non-consumable
new:  XRAiAssistant/Monetization/AdConsentStore.swift    UMP + ATT
new:  XRAiAssistant/Monetization/RemoveAdsSection.swift  purchase / restore / privacy options
new:  XRAiAssistant/PrivacyInfo.xcprivacy
new:  XRAiAssistantTests/AdPacingTests.swift             17 tests
new:  maigeXR.storekit                                   local product simulation
mod:  XRAiAssistant/Monetization/AdManager.swift         rewritten onto the seam
mod:  XRAiAssistant/Monetization/AdBannerView.swift      places an opaque view
mod:  XRAiAssistant/ContentView.swift                    banner + restraint signals + Settings
mod:  XRAiAssistant/XRAiAssistant.swift                  startMonetization()
mod:  XRAiAssistant/Config/AppConfig.swift               dead Unity config removed
mod:  XRAiAssistant.xcodeproj/project.pbxproj            bundle identifier
mod:  .../xcschemes/XRAiAssistant.xcscheme               StoreKit config reference
```

Verified: **BUILD SUCCEEDED** and **17/17 tests pass** (Xcode 26.6, iPhone 17 Pro
simulator). Bundle ID, ATT string and privacy manifest all confirmed present in
the built bundle.

Not run: physical device, release archive, a real purchase, and anything Android.

## Decisions — settled, do not re-litigate

1. **First release for both platforms.**
2. **`studio.seacloud9.maigexr`** on both. iOS is done. Irreversible once
   published.
3. **One non-consumable "Remove Ads"** plus Restore. Not a subscription.
   Product ID `studio.seacloud9.maigexr.removeads`.
4. **Rewarded ads cut from v1** — removed, not left dormant.

---

## Next actions

### Interstitial trigger — decided and wired 2026-10-05

Interstitials fire **only on leaving a scene**: the Chat tab button in
`ContentView.bottomTabBar` calls `AdManager.shared.onSceneRun()` when
`currentView` was `.scene`, 350 ms after the switch so the ad does not present
mid-transition. That is the only path from scene back to chat. Pacing and
restraint rules in `AdManager` still decide whether one actually shows.

### iOS console work — no code involved

- Create the AdMob app and the banner + interstitial units. Replace
  `GADApplicationIdentifier` in `Info.plist` (still Google's public sample) and
  fill `GADBannerUnitID` / `GADInterstitialUnitID`. Consider driving the app ID
  from a per-configuration build setting so a debug build cannot carry it.
- Register the non-consumable in App Store Connect and set a real price. The
  `2.99` in `maigeXR.storekit` is a local simulation value, not a decision.
- Register the App ID for `studio.seacloud9.maigexr` and check signing.
- Drive a purchase and a restore through the simulator against
  `maigeXR.storekit` — the flow has not been exercised even locally.
- Verify `PrivacyInfo.xcprivacy` against Xcode's privacy report of a real
  archive. It was derived from reading the repo, not from an instrumented build.

### Android — not started, different blockers

Separate repo, clean tree at `e9713f8`.

- `applicationId` is `com.xrai.assistant` → `studio.seacloud9.maigexr`. Leave
  `namespace = "com.xraiassistant"`; it is not store identity and renaming it is
  a wide, pointless refactor.
- **Release AdMob IDs are literal placeholders** —
  `ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY` in the `release` buildType.
- **No consent flow at all.** `user-messaging-platform:3.0.0` is declared and has
  **zero usages** in `app/src`.
- **`MobileAds.initialize()` runs unconditionally** in
  `XRAiAssistantApplication.onCreate()` — before consent, and ignoring
  `AppConfig.adsEnabled`, so it starts even in debug where `ADS_ENABLED=false`.
- **No `signingConfig`** for release, so no signed AAB is possible.
- `compileSdk`/`targetSdk` are **34**, likely below what Play accepts for a new
  app. **Verify against the live policy page — not from memory, not from the plan
  document.**
- Play Billing is not a dependency yet; decision 3 needs it.
- Remove the rewarded paths and `AdManager.RewardType` here too.
- The iOS work is the template: the same seam, the same entitlement shape, the
  same consent ordering. Porting it is the cheap path.

### Housekeeping

- **Delete `Podfile`.** CocoaPods was never installed and it has already misled
  this audit once. See the corrections section of `READINESS-AUDIT.md`.
- `XRAiAssistant/Info.plist.backup` is tracked and stale.
- `ContentView.swift` has three pre-existing deprecated `onChange(of:perform:)`
  calls (lines ~1104, 1193, 1533). Unrelated to this work.
- The target is still named `XRAiAssistant` internally. Only `CFBundleDisplayName`
  carries `m{ai}geXR`. Renaming the target is cosmetic and risky; the display
  name is what users see, so this is fine to leave.

## Mechanics worth keeping

- **No `.pbxproj` edits needed to add files.** The project uses
  `PBXFileSystemSynchronizedRootGroup` (`objectVersion = 77`) — anything under
  `XRAiAssistant/` is compiled automatically. Changing a build *setting* value is
  still a manual edit; the bundle ID change was four `sed` replacements verified
  with `xcodebuild -list`.
- **`@MainActor` default arguments do not work.** Default argument expressions are
  evaluated at the call site in a nonisolated context, so
  `entitlement: EntitlementSource = UnpurchasedEntitlement()` fails to compile.
  Take an optional and build inside the initializer. This bit twice — once in
  `AdManager`, once in the tests.
- UMP's Swift API drops the `UMP` prefix via `NS_SWIFT_NAME`:
  `ConsentInformation.shared`, `ConsentForm.loadAndPresentIfRequired(from:)`,
  `RequestParameters`, `DebugSettings` with `.geography = .EEA`. Verified against
  the 3.1.0 headers.
- UMP completion handlers are nonisolated closures, so anything they call must be
  `nonisolated` too — a `@MainActor` logger produces a warning now and an error
  under Swift 6.
- `XRAiAssistant/Monetization/` is all **LF**. The repo-wide CRLF hazard does not
  apply here, but check any new directory before scripted edits.
- Run iOS tests with `-destination` only. Adding `-sdk iphonesimulator` builds
  every package target for both archs and dies on swift-openapi-generator's
  `_OpenAPIGeneratorCore` `#error`, which looks like a broken build and is not.
- `gradlew` is not executable in `AndroidMaigeXr`; invoke it as `sh gradlew`.
- `CLAUDE.md` says the user verifies builds and that Claude should not run
  `xcodebuild` — but also that build verification after changes is mandatory.
  Builds were run here because the store plan requires evidence for any claim
  that something passes. Worth resolving that contradiction in `CLAUDE.md`.
