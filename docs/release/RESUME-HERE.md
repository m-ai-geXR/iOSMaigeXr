# Resume here — store-readiness work in progress

Updated 2026-10-05. A working note, not a deliverable: current state, what is
decided, and the next action. `READINESS-AUDIT.md` is the evidence; this is the
pointer.

---

## State

**Store readiness pass, 2026-10-05 evening.** Code-side blockers are closed:
privacy policy page drafted in `maige_xr_site/privacy.html` and linked from
Settings on both apps; Android shrinker rules fixed and a minified release build
verified on the emulator; iOS `ITSAppUsesNonExemptEncryption` and Google's 50
`SKAdNetworkItems` added; `Podfile` and `Info.plist.backup` removed (the backup
was being copied into the app bundle). What remains is console work, real IDs,
listing assets and device testing: see `SUBMISSION.md`, which also holds the
review notes and the App Privacy and Data safety answers.

**iOS monetization is code-complete, tested and committed.** Steps 1–5 of
`MONETIZATION.md` are done and the interstitial trigger is wired. What is left on
iOS is console work only. **Android is code-complete too; see below.**

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

- Done 2026-10-06: AdMob app and units created and set in `Info.plist` (IDs in
  `SUBMISSION.md` section 1a). Still open: the consent messages in AdMob.
- Register the non-consumable in App Store Connect and set a real price. The
  `maigeXR.storekit` simulates the decided price, $2.00.
- Register the App ID for `studio.seacloud9.maigexr` and check signing.
- Drive a purchase and a restore through the simulator against
  `maigeXR.storekit` — the flow has not been exercised even locally.
- Verify `PrivacyInfo.xcprivacy` against Xcode's privacy report of a real
  archive. It was derived from reading the repo, not from an instrumented build.

### Android — code-complete, console work left

Ported from the iOS template in `AndroidMaigeXr` on `feat/nova64-3d-library`:
the same `AdProvider` seam (`AdMobProvider` is the only `gms.ads` importer),
`BillingEntitlement` (Play Billing 9.1.0, one non-consumable, acknowledged,
Restore), `AdConsentStore` (UMP 3.2.0), and `AdManager` pacing. Rewarded ads
and the old `is_premium` SharedPreferences flag are gone. The ads SDK starts
only after the splash, entitlement and consent, never in `Application`.
Interstitials fire on leaving a scene, as on iOS. Verified:
`sh gradlew testDebugUnitTest assembleDebug` passes, 56 tests including 17 in
`AdPacingTest`.

- `applicationId` is `studio.seacloud9.maigexr`; `namespace` left alone.
- `compileSdk`/`targetSdk` are **36**. Checked against the live policy page on
  2026-10-05: since 2026-08-31 new apps must target API 36 (extension to
  2026-11-01 on request), and must use Billing Library 8 or later.
- **targetSdk 36 enforces edge-to-edge with no opt-out.** Not yet run on a
  device. Check the bottom bar, banner and Settings sheet against the system
  bars before submitting.
- Release secrets live in `AndroidMaigeXr/local.properties` (gitignored). A
  release build stops with a clear error until these are set:
  `maigexr.admob.appId`, `maigexr.admob.bannerId`, `maigexr.admob.interstitialId`,
  and for a signed AAB `maigexr.signing.storeFile`, `.storePassword`,
  `.keyAlias`, `.keyPassword`. Debug only: `maigexr.ump.debugGeography`
  (`eea`, `us`, `other`) and `maigexr.ump.testDeviceId`.

Console work:
- Create the upload keystore and enrol in Play App Signing.
- Create the Android AdMob app and banner + interstitial units.
- Register `studio.seacloud9.maigexr.removeads` as an in-app product in Play
  Console. Billing cannot be exercised until an AAB is on a test track and the
  tester account is a licence tester.
- Run a purchase, a restore and a refund through a licence tester.

Not run: physical device, release build, real purchase, UMP form in the EEA.

Known limit, accepted for v1: purchases are verified on the device only (no
backend). A rooted device can spoof Remove Ads. It unlocks nothing else, so the
exposure is lost ad revenue from that user. Server-side verification through the
Play Developer API is the fix if a purchase ever gates features.

### Housekeeping

- Done 2026-10-05: `Podfile` and `Info.plist.backup` deleted; Android keep rules
  now target `com.xraiassistant`, with the Retrofit rules R8 full mode needs. A
  minified release APK ran through chat, scene, favorites and settings with no
  crash. Network AI was not exercised (no key on the test device).
- **Security follow-up (iOS):** API keys are stored in UserDefaults and the app's
  SQLite settings table, not the Keychain, so they sit unencrypted in backups.
  Android already encrypts them. Move them to the Keychain before or soon after
  v1; the privacy policy deliberately claims encryption for Android only.
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
