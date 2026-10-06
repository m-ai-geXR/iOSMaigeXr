# Store submission guide

Updated 2026-10-05. Everything left between the code and a submitted build, for
both platforms. `RESUME-HERE.md` is the running status; this is the checklist and
the copy to paste into the consoles.

**These repositories are public.** Nothing below may be replaced with a real
secret in the repo. API keys, AdMob IDs, signing keys and the reviewer test key go
only into the store consoles or the gitignored `AndroidMaigeXr/local.properties`.

---

## 1. Values to fill in

| Value | Where | Notes |
|---|---|---|
| Privacy policy URL | `AndroidMaigeXr/app/build.gradle.kts` (`privacyPolicyUrl`), `iOSMaigeXr/XRAiAssistant/Config/AppConfig.swift` (`privacyPolicyURL`) | The page is `maige_xr_site/privacy.html`, served at `/privacy`. Android refuses a release build on the placeholder; iOS shows a compiler warning until it is set. Public, not a secret. |
| Publisher name, contact email | `maige_xr_site/privacy.html` (`[PUBLISHER]`, `[CONTACT EMAIL]`) | Public. Use an address you are happy to publish. |
| iOS AdMob app ID and units | `XRAiAssistant/Info.plist`: `GADApplicationIdentifier`, `GADBannerUnitID`, `GADInterstitialUnitID` | The app ID is still Google's public sample. AdMob IDs are not secret, but must be real before release. |
| Android AdMob IDs | `local.properties`: `maigexr.admob.appId`, `.bannerId`, `.interstitialId` | Gitignored. A release build stops until set. |
| Android upload key | `local.properties`: `maigexr.signing.storeFile`, `.storePassword`, `.keyAlias`, `.keyPassword` | Never commit the keystore or passwords. |
| Remove Ads price | App Store Connect, Play Console | `maigeXR.storekit` holds a local simulation value only. |
| Reviewer test key | App Store Connect review notes, Play Console App access | See section 3. Never in the repo. |

## 2. Console setup

**Apple**
- Register the App ID `studio.seacloud9.maigexr` and create the app record.
- Create the non-consumable `studio.seacloud9.maigexr.removeads` and set its price.
- Create the AdMob iOS app and its banner and interstitial units; fill section 1.
- Archive a Release build. Check Xcode's privacy report against section 4.
- Run a purchase and a Restore in the simulator against `maigeXR.storekit`, then in TestFlight sandbox.

**Google**
- Create the upload keystore and enrol in Play App Signing.
- Create the Android AdMob app and units; fill `local.properties`.
- Register `studio.seacloud9.maigexr.removeads` as an in-app product.
- Upload an AAB to internal testing, add a licence tester, and run a purchase, a Restore and a refund.
- Read the pre-launch report. Expect a note about the scene WebView allowing mixed content and file access; it is needed for the local playgrounds.

## 3. Reviewer access

The AI chat uses the user's own API key, so a reviewer cannot try it without one.
Create a key used only for review, with a low spending limit, on one provider
(Together AI is cheapest), and revoke it after approval.

**App Store Connect, App Review Information, Notes**

> m{ai}geXR turns plain-language prompts into interactive 3D scenes. It has no
> accounts. The AI chat uses the user's own API key for a provider such as
> Together AI; we have supplied a review key with a low spending limit.
>
> To test: open Settings (gear, bottom right), paste the key below into the
> Together AI field and tap Save. Back on the chat, keep the default model, ask
> "make a spinning neon cube", then tap Run Scene. Without a key, Run Demo on the
> welcome message shows a scene with no network AI at all.
>
> Remove Ads is a single non-consumable in Settings, with Restore.
>
> Review key: [paste here in App Store Connect only]

**Play Console, App content, App access**: choose "All or some functionality is
restricted", and add an instruction with the same steps and the same key.

## 4. Apple App Privacy answers

Answer "Yes, we collect data". The app has no analytics of its own; the entries
come from the Google Mobile Ads SDK (per Google's iOS data disclosure guide) and
from user content sent to the chosen AI provider. Re-check against Google's guide
at submission time, as it changes.

| Data type | Purposes | Linked to user | Used for tracking |
|---|---|---|---|
| Coarse Location (from IP) | Third-Party Advertising, Analytics | No | Yes, if the user allows tracking |
| Device ID | Third-Party Advertising, Analytics | No | Yes, if the user allows tracking |
| Product Interaction | Third-Party Advertising, Analytics | No | Yes, if the user allows tracking |
| Advertising Data | Third-Party Advertising, Analytics | No | Yes, if the user allows tracking |
| Crash Data | App Functionality | No | No |
| Performance Data | Analytics | No | No |
| Other User Content (prompts, images) | App Functionality | No | No |

The app asks for App Tracking Transparency before using the IDFA, so tracking
applies only with permission. `PrivacyInfo.xcprivacy` declares the app's own
behaviour (`NSPrivacyTracking` false, Other User Content); the ads SDK ships its
own manifest, and Xcode's privacy report merges them.

## 5. Google Play Data safety answers

- Does the app collect or share user data? **Yes.**
- Is all user data encrypted in transit? **Yes** (TLS everywhere; cleartext is disabled).
- Can users request deletion? **Yes**: in-app history deletion and uninstall. Ad ID reset is in Android settings.

| Data type | Collected / shared | Purposes | Optional |
|---|---|---|---|
| Approximate location (from IP) | Collected and shared (AdMob) | Advertising, Analytics, Fraud prevention | No |
| Device or other IDs (advertising ID, app set ID) | Collected and shared (AdMob) | Advertising, Analytics, Fraud prevention | No |
| App interactions | Collected and shared (AdMob) | Advertising, Analytics | No |
| Diagnostics, other app performance data | Collected (AdMob) | Analytics | No |
| Other user-generated content (prompts, images) | Shared with the AI provider the user selects | App functionality | No |

The app declares `com.google.android.gms.permission.AD_ID` through the ads SDK,
so answer **Yes** to the advertising ID question.

## 6. Content rating and category

- **Category:** Developer Tools (Apple), Tools (Play). Education is a reasonable
  alternative.
- **Age rating:** answer the questionnaires honestly. The app has no
  user-to-user communication. It displays AI-generated text and code, and scenes
  load scripts from the web, so expect the unrestricted web access question to
  apply.

## 7. Listing assets

| Asset | Apple | Google Play |
|---|---|---|
| Icon | From the asset catalog (done) | 512×512 PNG, from `maigeXR-avatar.jpg` |
| Phone screenshots | 6.9-inch iPhone, at least 3 | 2 to 8, 9:16 or 16:9 |
| Tablet screenshots | 13-inch iPad (required: the app supports iPad) | 7-inch and 10-inch, for the tablet listing |
| Feature graphic | n/a | 1024×500 |
| Text | Name, subtitle, description, keywords, promotional text | Short (80) and full description |

The ad banner shows Google's test creative in debug builds; take screenshots from
a build with ads off, or crop the banner out.

## 8. Before pressing submit

- [ ] Section 1 values filled; no placeholder or sample ID left
- [ ] Release archive (iOS) and signed AAB (Android) built and installed on a real device
- [ ] One real chat in the release build (minified Android builds were only checked without network AI)
- [ ] Phone layout checked on Android with targetSdk 36 edge-to-edge
- [ ] Consent form seen with debug geography set to EEA
- [ ] Purchase, Restore and (Android) refund exercised
- [ ] Privacy policy URL opens from Settings on both apps
