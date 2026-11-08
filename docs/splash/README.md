# m{ai}geXR × Nova64 launch identity

November 7, 2026. Implemented on branch `feat/nova64-brand-splash`.

The intro follows the cobalt, cream, Archivo, square-cornered brand system from
https://maigexr.seacloud9.studio/ and `brand/brand.json`. It combines the existing
hooded mascot and wordmark with a luminous orbital portal. The mascot sits
inside the aperture; the centered mobile wordmark gives the scene a clear focal
point. Landscape and tablet layouts place the portal beside the wordmark.
The scene is a real Nova64 cart, using the hosted https://nova64.io/hero-embed
studio runner and its EXECUTE_READY → EXECUTE_CODE → EXECUTE_SUCCESS protocol.

Brand identity and font are bundled. A static orbital motif appears before the
runtime is ready, when offline, or when reduced motion is enabled. The live scene
requires a connection. There is no audio or artificial progress indicator.
The intro has no Enter button or other required interaction. It appears and
automatically fades out: after 5 seconds without a runtime response, or 2.4 seconds
after successful execution, with a native 6-second deadline. Browser previews use
a 650 ms opacity fade; native apps retain the live scene through their existing
600 ms crossfade into the app. Dismissal is idempotent and releases the runtime
after the transition.
A feathered elliptical alpha mask reaches zero opacity before each canvas edge,
so bloom and particles merge into the surrounding background without a rectangle.
The cart explicitly disables Nova64 touch controls on phones and tablets.

No native JavaScript interface is exposed to the remote frame; the host handles
only a main-frame `maigexr://splash/dismiss` navigation.

## Effects refinement

At the user’s request, the intro now demonstrates Nova64 post-processing:

- Three smooth emissive rings (96 segments each) with gentle precession.
- Bloom: strength 0.8, radius 0.65, threshold 0.75.
- Subtle chromatic aberration (0.0015), vignette, and FXAA.
- Two instanced particle pools, capped at 240 ambient motes and 96 portal sparks.
  The ambient field is seeded on initialization, so it is visible immediately.
- The runner renders on black and blends into the cobalt backdrop, preserving
  deep shadows under bloom. The identity stays outside the effects pass.
- Runner resolution is capped at 720 on its longest edge with aspect preserved;
  rotation reboots the runner at the new aspect ratio.

Updated HTML is synchronized to both platforms. Chromium and WebKit live-runtime,
layout, offline, reduced-motion, and dismissal checks passed after refinement;
the updated Android debug APK also builds. Native host code was unchanged in
this refinement, and no iOS Xcode build was run.

## Source and preview

- Android source: `app/src/main/assets/splash.html` and `assets/splash/`.
- Android host: `ui/components/SplashScreen.kt`.
- iOS host: `XRAiAssistant/SplashWebView.swift` and `SplashScreenView.swift`.
- iOS HTML embeds font and mascot as data URLs for offline availability.
- Synchronize future visual changes from the Android checkout:
  `python3 scripts/sync-ios-splash.py ../.ios-templates-wt`
- Preview from the Android checkout:
  `python3 -m http.server 8769 --directory app/src/main/assets`
  then open `http://localhost:8769/splash.html?preview=1` to see the automatic
  fade. For a stationary screenshot, use `?hold=1`; native apps always use the
  timed path and ignore the screenshot hold.

Screenshots: [phone](phone.png), [landscape](landscape.png), [iPad Mini](tablet.png).
Archivo is redistributed under the bundled SIL Open Font License.

## Verification

- Android Kotlin compile, debug APK build, and 130 unit tests passed.
- Chromium: actual Nova64 cart execution succeeded, with no page errors.
- Phone, small phone, landscape, tablet, offline identity, reduced motion,
  automatic fading and offline automatic dismissal passed browser checks.
- WebKit: embedded iOS HTML, actual Nova64 execution and dismissal passed
  at 390×844 and 1024×768.
- Android emulator: native WebView identity and viewport rendering were verified;
  runtime boot and code execution were observed in device logs. Main app opened
  after dismissal. The viewport uses measured pixels to avoid zero-height vh
  units during the Android launch transition.
- Swift parser accepted both changed Swift sources. Xcode build/device validation
  remains with the user according to the iOS repository's build instructions.

The store release 1.1.0/code 12 was already submitted before this change. This
splash is a source change for a future build; no store version was bumped or uploaded.

### Seam and automatic-fade verification

Chromium at 390×844, 768×1024 and 1358×949, plus WebKit at 768×1024,
verified the live runtime with touch emulation: no Enter button or runtime
gamepad. Canvas-edge pixels were compared with the identical page with its stage
hidden; maximum per-channel difference was 1/255 in Chromium and 0 in WebKit.
Online, offline and reduced-motion timed paths all passed; opacity samples
confirmed intermediate values during the fade and zero at completion. Updated
Android debug APK build and Swift syntax parsing passed.
