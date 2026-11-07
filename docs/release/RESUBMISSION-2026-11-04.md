# Resubmission after November 4, 2026 review

Submission: `3642846a-012f-4d74-b59e-db26effba94b`. Rejected build: 1.0 (12).
Prepared replacement: **1.0 (13)**. This document supersedes the October reply
for these two issues. Resubmitted November 4 at 8:24 PM Pacific; verified Waiting for Review.

## Current handoff

- Source branch: **fix/app-review-att-consent**, based on `main` / `origin/main`
  at `a6addc2` (freshly fetched and verified). The separate
  `post-approval/nova64-game-templates` branch preserves commit `fdc1052`.
  Git's reflog confirms that feature branch was created after build 13 was
  archived and uploaded; the uploaded build excludes that later feature work.
  Source changes are committed locally as `5187ff1`.
- Build 13 was exported, uploaded, processed and verified **Ready to Submit**
  in TestFlight. It is now selected on version 1.0, saved and verified after
  reloading App Store Connect.
- China mainland was excluded; privacy-label corrections were published.
- AdMob publisher `pub-4166973145998533` now has **maigeXR GDPR** and
  **maigeXR US states**, both verified **Published** for **2 apps** (iOS and
  Android), as requested. Both use
  `https://maigexr.seacloud9.studio/privacy`, verified HTTP 200.
  GDPR provides Consent, Do not consent and Manage options; rejection is
  enabled for all 33 country/region entries. US opt-out is enabled.
  Overview shows one active message in each regulation category.
- The previous UMP "no forms configured" failure is resolved. A simulator
  launch reached the native ATT request, and an automated UI test declined
  tracking and verified the app remained usable and the scene WebView became
  visible and interactive. This does not assert that a complete 3D scene
  finished rendering or that all SDK traffic has been audited.
- Review Notes were updated and saved with the corrected consent configuration,
  China mainland exclusion, ATT reproduction instructions and accurate simulator
  validation status. Existing reviewer access/setup instructions were preserved
  inside App Store Connect without exposing any reviewer key. Save state and
  build selection were verified after a full page reload.
- Physical Release build 13 was installed on the connected iPad Pro 11-inch
  (2nd generation), iPadOS 26.5, using an explicit development profile with
  the installed app's T28W526VKC prefix. The same archived build was exported
  for the device; no source changes or app-data deletion were needed.
- A physical-device UI check passed (one test, zero failures). Native ATT was
  visually verified in the actual USB video; a custom XCTest interruption
  handler selected **Ask App Not to Track**. Normal navigation and an animated
  Nova64 scene rendered afterward. The global tracking-request switch was
  already on; only maigeXR's authorization was reset using XCTest.
- The final 47-second H.264 landscape recording is
  `resubmission-evidence/2026-11-04/Physical-iPad/maigeXR-build13-physical-iPad-ATT-landscape.mp4`
  relative to the workspace root. It was uploaded to App Review Information's
  Attachment field. Review Notes now identify the recording, physical device,
  exact OS and permission-reset flow, preserving existing reviewer access.
  The physical iPad was not on 27.2; no claim of physical 27.2 testing is made.
- **Resubmitted November 4, 2026 at 8:24 PM Pacific**, at the user's explicit
  request. App Store Connect confirms **Waiting for Review** for both iOS App
  1.0 (13) and maigeXR Remove Ads. Submission ID remains
  `3642846a-012f-4d74-b59e-db26effba94b`.
- Sent a new App Review reply addressing Guidelines 2.1 and 5, with the physical
  video attached directly to the message as well as App Review Information.
  The reply states the actual iPadOS 26.5 device, permission-reset flow,
  consent configuration fix and China mainland exclusion. The video finished
  processing and the attachment/Review Notes persisted after reload.



## Changes

- Preserve AI features; exclude **China mainland** from App Store availability.
  Do not claim a China-specific functionality suppression. Verify the saved
  availability after changing it; Hong Kong, Macau and Taiwan are separate rows.
- ATT waits for an active app, an attached presenter and settled transitions.
- An interrupted/undetermined ATT result gets one further presentation attempt.
  If still unanswered, no ad SDK starts; foregrounding can retry consent.
- Overlapping startup/consent calls share a single resolution. StoreKit product
  pricing loads independently so it cannot hold up the consent request.
- Foregrounding rechecks system ATT status and discards prepared ads when
  authorization changed in Settings.
- Paid Remove Ads users skip ad consent; UMP failure blocks ads and logs the
  failure instead of claiming consent. UMP still precedes ATT.
- Release diagnostics use the `AdConsent` category in subsystem
  `studio.seacloud9.maigexr`. ATT values: 0 undetermined, 1 restricted, 2 denied,
  3 authorized. Diagnose UMP errors in AdMob; do not bypass regional consent.

## Physical-device evidence required

Physical capture is now complete on the connected iPad Pro 11-inch
(2nd generation), iPadOS 26.5. Simulator artifacts are not the physical evidence.
The following checklist remains useful for reproducing the capture.

1. Archive build 13 in Release configuration and distribute through TestFlight.
   Confirm the installed build is 13, not a Debug build (ads are disabled by
   default in Debug unless `ENABLE_ADS=true`).
2. Use a test account without the Remove Ads entitlement. Reinstalling does not
   remove an existing StoreKit purchase. Verify Settings > Privacy & Security >
   Tracking allows apps to request tracking and the app starts undetermined.
   A restricted/managed/child account may suppress the prompt legitimately.
3. In AdMob > Privacy & messaging, verify required messages are published for
   the iOS app ID in Info.plist. UMP returning an error or disallowing ad requests
   prevents the ATT step. Check release-device logs if the prompt is absent.
4. Start recording on the Home Screen, launch the freshly installed app, let the
   splash finish, complete any regional consent form, show the native ATT
   request and answer it, then demonstrate Run Demo and normal navigation.
   No API key is needed for Run Demo. Avoid recording keys or private prompts.
5. Separately test both Allow and Ask App Not to Track, an existing decision,
   background/foreground during startup, offline UMP failure, and Remove Ads.
   The app must remain usable after denial. An unanswered request or failed
   UMP update must leave ads off. Check SDK/network behavior as well as UI;
   a screen recording alone cannot prove absence of tracking traffic.
6. Inspect the signed archive's Info.plist and Xcode privacy report. Confirm
   `NSUserTrackingUsageDescription`, build number 13, and the app/SDK combined
   disclosures against actual behavior. Do not mark tracking "No" merely
   because some users decline ATT or requests carry `npa=1`.
7. Attach the physical-device recording to the App Review reply and put its
   filename/reference (or accessible video link) in App Review Information >
   Notes. Preserve existing reviewer access instructions and enter any review
   key only in App Store Connect.

## Reply draft — complete brackets only after verification

Hello, thank you for the clarification.

For Guideline 5, we have deselected China mainland in the app's availability
settings. We are distributing this version only in the remaining selected
storefronts.

For Guideline 2.1, we corrected the advertising consent-message configuration
that had prevented startup from reaching the ATT request. Build 1.0 (13) also
now waits for the app to be active and the
presentation transition to finish before requesting App Tracking Transparency.
The ad SDK is initialized only after the required consent flow has resolved.
An unanswered ATT request keeps ads disabled. Users who deny ATT can continue
using the app with nonpersonalized ads where regional consent permits.

We tested on a physical [DEVICE] running [OS VERSION]. The attached recording,
[FILENAME], shows [FRESH INSTALL OR PERMISSION RESET], launch, [REGIONAL CONSENT
FORM IF APPLICABLE], the ATT permission request and the subsequent app flow.
The recording reference and reproduction instructions are included in App
Review Information > Notes.

To reproduce: use an account without Remove Ads, with tracking requests allowed
in system settings and no existing ATT decision for the app. Launch the app,
wait for the splash to finish and complete any required regional consent form.
The ATT request then appears. Existing decisions, system tracking restrictions,
or a Remove Ads entitlement can legitimately suppress the request.

Thank you,
Brendon Smith, SeaCloud9

## Notes addendum — complete after recording and upload

November 4 review follow-up: replacement build 1.0 (13).
China mainland is excluded from availability.
Physical-device ATT recording: [FILENAME / ACCESSIBLE LINK], [DEVICE], [OS].
Recording begins from [FRESH INSTALL / RESET] and shows the native permission
request followed by Run Demo. ATT is requested after the splash and any required
regional consent, before initializing ads. Use a test account without Remove
Ads and enable tracking requests in system settings to reproduce.

## Release gates

- [x] China mainland exclusion saved and verified in App Store Connect on
  November 4: 174 selected storefronts; China mainland status was
  "Processing to Not Available". Apple says propagation may take 24 hours.
- [x] Focused ATT and ad-pacing tests pass; Release archive succeeds.
- [x] GDPR and US-state messages published and verified for both apps.
- [ ] Physical device flows and SDK behavior checked; recording captured.
- [x] Signed archive manifests inspected and App Privacy answers corrected
  against SDK declarations; final runtime behavior remains in the device gate.
- [x] Build 13 uploaded and processed; verified Ready to Submit in TestFlight.
- [x] Build 13 selected on version 1.0; saved and verified after reload.
- [x] Review Notes updated and saved, with existing reviewer access preserved.
- [ ] Physical recording attached/referenced; pending-recording sentence replaced
  with the actual device/OS/recording details; final reply prepared for sending.
- [ ] Resubmit version 1.0 with the existing Remove Ads purchase attached.

## Validation recorded during preparation

- Xcode 27.2, iPad Air 11-inch (M4) simulator on iPadOS 27.0:
  **23 tests passed, zero failures** (6 TrackingAuthorizationTests and
  17 AdPacingTests). This verifies interrupted requests retry, existing
  decisions are respected, cancellation avoids presentation, retries are
  bounded, and unknown/denied consent cannot start an ad provider.
- Test result bundle:
  `/tmp/maigexr-resubmission-build/Logs/Test/Test-XRAiAssistant-2026.11.04_10-28-20--0800.xcresult`.
- Limited build concurrency after the initial unrestricted build overloaded
  the host: use `-jobs 3 -parallel-testing-enabled NO ONLY_ACTIVE_ARCH=YES`
  and `OTHER_SWIFT_FLAGS='$(inherited) -j3'`. The initial run was interrupted;
  the limited run completed successfully.
- Info.plist, PrivacyInfo.xcprivacy and the Xcode project pass `plutil -lint`;
  `git diff --check` passes.
- Release archive **succeeded**, signed with the existing Apple Development
  identity. Deep/strict code-signature verification passed. Version 1.0 (13),
  bundle `studio.seacloud9.maigexr`, and the updated ATT usage string are present
  in the signed app. Archive:
  `/Users/brendonsmith/Library/Developer/Xcode/Archives/2026-11-04/maigeXR-1.0-13.xcarchive`.
  Distribution export/signing is a separate step from the development-signed
  archive; this does not mean build 13 has been uploaded or submitted.
- App Store distribution export was attempted and **blocked by Apple**:
  "PLA Update available" requires the Account Holder to review/accept the
  latest Developer Program License Agreement. The exporter also reports no
  local iOS Distribution signing certificate/private key for team T28W526VKC.
  Retry automatic distribution signing after the agreement is accepted; if
  still missing, provision or restore the distribution identity through Xcode.
  No App Store-signed IPA was produced and nothing was uploaded.
  **Resolved later on November 4:** the user accepted the agreement, automatic
  distribution signing then succeeded, and the App Store export completed.
  The signed package is
  `/Users/brendonsmith/exp/maigeXR/resubmission-evidence/2026-11-04/AppStore/XRAiAssistant.ipa`.
  Build 13 was absent from TestFlight before starting its upload.
  **Upload succeeded** (`Uploaded XRAiAssistant`, `EXPORT SUCCEEDED`). Build 13
  subsequently finished processing and was verified Ready to Submit in TestFlight.
  After the user restored sign-in, build 13 was selected and saved on version
  1.0. The selected build and the new Review Notes persisted after reload.
  Upload returned warnings about missing vendor dSYMs for GoogleMobileAds and
  UserMessagingPlatform; these did not block upload and affect symbolication
  inside those vendor frameworks.
- Fresh simulator launch with `ENABLE_ADS=true` reproduced a concrete blocker:
  UMP returned "Failed to read publisher's account configuration; no form(s)
  configured for the input app ID" for
  `ca-app-pub-4166973145998533~6620905705`. The app kept ads off and did not
  request ATT. Publish consent messages for this exact app in its owning AdMob
  publisher account before claiming the issue is resolved.
- After the user signed in to AdMob, the privacy-message creation UI appeared
  associated with `pub-2702873073469771`, which differs from the build's
  `pub-4166973145998533`. No messages were created in that session. The owning
  publisher account must be confirmed before changing configuration.
  **Resolved later on November 4:** after the user's account switch and a page
  reload, the European-regulations iframe explicitly identifies
  `publisher_code=pub-4166973145998533`, matching the signed app. Its message
  list initially was empty. **Now resolved:** privacy-policy URLs were added,
  both regulation messages were autofilled, published and verified for both
  apps. The Safari editor requires reading its embedded frames and keeping the
  tab active; UI controls in background tabs can appear unresponsive.
- Simulator-only launch video and screenshots are in
  `/Users/brendonsmith/exp/maigeXR/resubmission-evidence/2026-11-04/`.
  The earlier `SIMULATOR-ONLY-launch-build13.mp4` demonstrates the initial
  configuration failure. The later `SIMULATOR-ONLY-ATT-denial-and-demo-build13.mp4`
  and `Simulator-UI-test-final/` show the fixed native ATT flow on the simulator.
  Neither recording fulfills the requested physical-device proof.
- Final simulator UI result: **1 test passed**, zero failures, in
  `/tmp/maigexr-att-smoke-build/Logs/Test/Test-Smoke-2026.11.04_19-48-55--0800.xcresult`.
  The temporary harness is `/tmp/maigexr-att-smoke/SmokeTests.swift`. It launches
  the existing build 13 Debug app with test ads and debug geography `other`,
  waits for native ATT, selects Ask App Not to Track, checks the app remains
  usable, and checks the scene WebView is visible/hittable. The preceding
  23 focused unit tests remain the code-side regression checks. The UI harness
  and video do not represent a Release build on a physical device.

## Privacy disclosure reconciliation

The live App Store privacy label was inspected on November 4. Initially it declared
tracking for Coarse Location, Device ID, Product Interaction and Advertising
Data, and listed all seven collected types as not linked to identity. Retain
tracking declarations while the ad-supported tracking model remains in use.

The **signed build 13 archive** embeds Google Mobile Ads 13.0.0's manifest,
which declares Coarse Location, Device ID, Product Interaction and Advertising
Data as linked. This contradicted the existing blanket "not linked" answers in
SUBMISSION.md and App Store Connect.
Google's manifest also listed Other Diagnostic Data, absent from the original
seven-type App Store label, and Analytics for Crash Data (originally only App
Functionality in the label). UMP additionally declares App Functionality for
Coarse Location, Product Interaction and Performance Data.

Use these archive findings as the baseline for correcting the questionnaire,
checking actual SDK behavior and the publisher's configuration. The SDK manifest
contains capabilities/default declarations, not proof that every listed
purpose occurs in this app; do not blindly copy unused Developer Advertising
purposes or remove declared tracking just because some fields in a manifest
say false. AIProxy's embedded manifest also declares device IDs and IP addresses;
review the direct-service path actually exercised by the app.

**Corrections published and verified in App Store Connect on November 4:**
Coarse Location, Device ID, Product Interaction and Advertising Data now declare
linkage to identity; their existing tracking declarations remain enabled.
App Functionality was added to Coarse Location and Product Interaction for UMP,
and to Performance Data alongside Third-Party Advertising and Analytics.
Crash Data retains App Functionality and now includes Analytics. Other Diagnostic
Data was added with Third-Party Advertising/Analytics, not linked, not tracking.
The live label now contains eight fully configured types, with no setup warning.
SUBMISSION.md's answer table reflects these changes. Developer Advertising was
not added because this app does not use the SDK for its own marketing campaigns.

References: [Google disclosure guidance](https://developers.google.com/admob/ios/privacy/data-disclosure)
and [Apple privacy definitions](https://developer.apple.com/app-store/app-privacy-details/).

Sources: [Apple ATT documentation](https://developer.apple.com/documentation/apptrackingtransparency/attrackingmanager/requesttrackingauthorization(completionhandler:)),
[Google UMP setup](https://developers.google.com/admob/ios/privacy),
[Google privacy strategies](https://developers.google.com/admob/ios/privacy/strategies),
[Apple availability settings](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store/).

## Physical capture provenance — November 4 evening

Final take: `PHYSICAL-IPAD-build13-ATT-landscape-take4.mov`, captured through
AVFoundation from the USB muxed display input named Brendon's iPad. The final
MP4 trims three seconds from the beginning and ends at 50 seconds of that
continuous take; it adds no simulated UI, overlays or replacement frames.
Video is H.264, 1718 x 1200, 30 fps, 47 seconds, 4,231,099 bytes, without audio.
The test result is
`/tmp/maigexr-physical-smoke-build/Logs/Test/Test-Smoke-2026.11.04_20-20-36--0800.xcresult`.
Exported prompt, post-denial and scene screenshots are under `Physical-iPad/UI-test`.
Earlier takes are retained locally but are not the uploaded evidence. Early
harness checks missed the native sheet in the accessibility tree; the final
custom interruption handler explicitly tapped Ask App Not to Track, verified
in the test log and video. A video demonstrates the UI flow, not a packet-level
traffic audit. Development signing was used only to install the archived app
on hardware; the selected App Store build remains the distribution upload.

Final recording SHA-256: `42a4b57315929318b721d672ae259e7062d2b08b97a8e3561975e0fcaa6e4c66`.
