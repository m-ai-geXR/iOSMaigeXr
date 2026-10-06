# Monetization — free with ads, paid without

This is the section the original plan did not cover. It is written against the
code as it exists, not as a greenfield design; see `READINESS-AUDIT.md` for what
is actually there today.

## The model

| Tier | Price | Ads | Everything else |
|---|---|---|---|
| **Free** | £0 | Banner + paced interstitial | Full feature set |
| **Paid** | one-off purchase | None | Identical |

**The paid tier removes ads and nothing else.** That is a deliberate constraint,
and it is worth stating plainly because it decides a lot:

- Nothing has to be gated, so there is no feature matrix to maintain, no "is
  this allowed" check scattered through the app, and no second code path to test.
- Both tiers behave identically for review, so a reviewer sees the whole product
  without needing a purchase.
- If the entitlement check ever fails, the user keeps their app and sees ads.
  A failure is an annoyance, not a lockout. The opposite design fails badly.

If you later gate features, that is a different product decision with a much
larger testing surface. Worth resisting for v1.

### One-off purchase, not a subscription

Recommended, unless you have a reason otherwise:

- "Remove ads" is a classic non-consumable. Users understand it.
- A subscription implies ongoing delivered value. Ad removal alone is thin
  justification and invites refunds and poor reviews.
- Non-consumables need **restore**, which is simple. Subscriptions need renewal,
  expiry, grace periods, billing retry, and server notifications.

Keep the entitlement as one non-consumable product. Revisit only if a paid tier
later carries real recurring cost, such as hosted inference.

---

## Swappable ad providers

You asked for this explicitly, and the current code is the opposite: `AdManager`
imports `GoogleMobileAds` and publishes AdMob types in its own API, so the
network is baked into every call site.

### The shape

One protocol, one adapter per network, one place that chooses:

```
        ┌──────────────────────────────┐
        │  App  (views, view models)   │
        └──────────────┬───────────────┘
                       │  knows only this
        ┌──────────────▼───────────────┐
        │  AdProvider  (protocol)      │
        │  initialize / banner /       │
        │  interstitial / rewarded     │
        └──────────────┬───────────────┘
           ┌───────────┼────────────┬─────────────┐
     ┌─────▼─────┐┌────▼──────┐┌────▼──────┐┌─────▼──────┐
     │  AdMob    ││ AppLovin  ││  Unity    ││  NoAds     │
     │  adapter  ││ adapter   ││  adapter  ││ (paid tier)│
     └───────────┘└───────────┘└───────────┘└────────────┘
```

Rules that make the swap actually cheap:

1. **No network type crosses the protocol.** No `BannerView`, no `GADRequest`.
   The banner is returned as an opaque view the app can place. The moment an
   AdMob type appears in a signature, the abstraction has leaked and the swap
   stops being cheap.
2. **The paid tier is a provider, not a branch.** `NoAdsProvider` returns nothing
   and does nothing. There is then exactly one `if` about entitlement in the
   whole app — the one that picks the provider — instead of a `guard
   !isPremiumUser` in every method, which is what the code does today.
3. **Pacing lives above the provider.** Frequency, cooldowns, and "never during
   generation" are product rules. They belong in the manager so every network
   inherits them and a swap cannot quietly change how often users see ads.
4. **Consent lives above the provider too.** One consent result, passed down.
   Each adapter translates it into whatever its SDK wants.

### Swapping, concretely

Adding a network should be: write an adapter, register it, change one value.
Removing one should be deleting a file. If it is ever more than that, the
abstraction has drifted and should be corrected rather than worked around.

A provider that fails to initialise must degrade to no ads, not crash and not
block the UI. Ad SDKs are third-party code on the startup path.

---

## What has to be built

In dependency order.

### 1. Provider abstraction — `AdProvider` + `AdMobProvider` + `NoAdsProvider`

Decouples the app from AdMob. Everything else builds on it. **Started; see
below.**

### 2. StoreKit entitlement

Replace the `UserDefaults` boolean with a real one:

- One non-consumable product, defined in App Store Connect.
- Read entitlement from StoreKit's current entitlements, and keep listening for
  transaction updates, so a purchase on another device applies here.
- A visible **Restore Purchases** control. Apple requires it.
- Cache the last known state for offline launches, but treat StoreKit as the
  source of truth whenever it answers. Cache for convenience, never for
  authority.

Local-only entitlement is the current state and is not acceptable for a paid
product.

### 3. Consent, before any ad loads

- **ATT** prompt plus `NSUserTrackingUsageDescription`, or no IDFA.
- **A CMP** for EEA/UK users before personalised ads. `GoogleUserMessagingPlatform`
  is already in the `Podfile` and unused.
- Non-personalised ads must still work for users who decline. Declining is not
  an error state.

### 4. Real ad units

Replace the test IDs. Keep test IDs on debug builds — serving live ads to your
own development devices risks the AdMob account.

### 5. Placement and pacing

Decide deliberately, then write it down:

- Banner: where, and whether it ever overlaps the editor or canvas.
- Interstitial: the existing `AppConfig` scene-count and interval rules are a
  reasonable base.
- **Never interrupt a generation in flight, and never cover an error.** An ad
  shown while a user waits on a slow reasoning model reads as a broken app.
- Rewarded: decide whether it is in v1 at all. It is the most review-sensitive.

---

## Store disclosure consequences

Ads change what must be declared, and these are easy to get wrong:

- The listing must state the app contains ads, and Play has a specific
  declaration for it.
- Apple's privacy questionnaire and Play's Data safety form must reflect what
  the **ad SDK** collects, not only what the app collects. AdMob collects device
  and advertising identifiers, so answering only for first-party code is wrong.
- The privacy manifest must list the ad SDK and its reasons.
- Age rating questionnaires ask about advertising.
- If the paid tier is sold, that is a digital purchase and must go through the
  platform's own billing.

The honest summary: **adding ads adds more disclosure work than engineering
work.** Budget for it.

---

## Open questions for you

1. **Price and name** for the paid tier. "Remove Ads" is clearest; "Pro" implies
   features that do not exist.
2. **Ad networks.** AdMob is wired up. Is a second network actually planned, or
   is swappability insurance? Both are reasonable; it changes whether a
   mediation layer is worth it now.
3. **Rewarded ads in v1?** Code exists. They need a reward worth granting, and
   there isn't an obvious one if the paid tier only removes ads.
4. **Bundle identifier.** Needs choosing before anything else; it cannot be
   changed later. Something like `studio.seacloud9.maigexr`.
5. **Does the free tier stay fully functional?** This plan assumes yes.
