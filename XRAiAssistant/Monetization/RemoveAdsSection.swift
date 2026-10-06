//
//  RemoveAdsSection.swift
//  m{ai}geXR
//
//  The Settings section for the one purchase this app sells.
//
//  Restore Purchases is here because Apple requires a visible restore path for
//  a non-consumable, and it stays visible after purchase so a user on a second
//  device can find it.
//

import SwiftUI
import StoreKit

struct RemoveAdsSection: View {
    @ObservedObject private var store = StoreEntitlement.shared
    @ObservedObject private var consent = AdConsentStore.shared

    var body: some View {
        Section("Ads") {
            if store.isEntitled {
                purchased
            } else {
                offer
            }

            restoreButton
            status
            privacyOptionsButton
        }
    }

    // MARK: - Privacy options

    /// A standing control, not a one-time prompt. When UMP reports that privacy
    /// options are required, the user must be able to change their mind later —
    /// showing the consent form once at launch does not satisfy that.
    @ViewBuilder
    private var privacyOptionsButton: some View {
        if consent.privacyOptionsRequired {
            Button("Privacy options") {
                Task { await consent.presentPrivacyOptions() }
            }
        }
    }

    // MARK: - Purchased

    private var purchased: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.brandSuccess)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ads removed")
                    .font(.system(size: 15, weight: .semibold))
                Text("Thank you for supporting m{ai}geXR.")
                    .font(.caption)
                    .foregroundColor(.brandMuted)
            }
        }
    }

    // MARK: - Offer

    private var offer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Remove ads")
                .font(.system(size: 15, weight: .semibold))

            // States the whole deal plainly. Every feature stays available on
            // the free tier, so this must not imply otherwise.
            Text("A one-off purchase that removes banner and full-screen ads. Everything else in the app is unchanged — nothing is locked behind it.")
                .font(.caption)
                .foregroundColor(.brandMuted)

            Button(action: buy) {
                HStack {
                    if store.state == .purchasing {
                        ProgressView().controlSize(.small)
                        Text("Purchasing…")
                    } else {
                        Text(buttonTitle)
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.brandAccent)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isBusy || store.product == nil)
        }
        .padding(.vertical, 4)
    }

    /// The price always comes from StoreKit — never hardcoded, because the
    /// user's currency and the store's formatting are not ours to guess.
    private var buttonTitle: String {
        if let price = store.product?.displayPrice {
            return "Remove ads — \(price)"
        }
        return store.state == .loadingProduct ? "Loading…" : "Unavailable"
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button(action: restore) {
            HStack {
                if store.state == .restoring {
                    ProgressView().controlSize(.small)
                }
                Text("Restore Purchases")
            }
        }
        .disabled(isBusy)
    }

    // MARK: - Status

    @ViewBuilder
    private var status: some View {
        switch store.state {
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundColor(.brandError)
        case .pending:
            Text("Your purchase is waiting for approval. Ads will switch off automatically once it completes.")
                .font(.caption)
                .foregroundColor(.brandWarning)
        default:
            EmptyView()
        }
    }

    // MARK: - Actions

    private var isBusy: Bool {
        switch store.state {
        case .purchasing, .restoring, .loadingProduct: return true
        default: return false
        }
    }

    private func buy() {
        Task {
            store.clearStatus()
            await store.purchase()
        }
    }

    private func restore() {
        Task {
            store.clearStatus()
            await store.restore()
        }
    }
}
