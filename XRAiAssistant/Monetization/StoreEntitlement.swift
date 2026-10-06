//
//  StoreEntitlement.swift
//  m{ai}geXR
//
//  The real entitlement, from StoreKit.
//
//  Replaces the `UserDefaults.standard.bool(forKey: "XRAiAssistant_IsPremium")`
//  check that used to stand in for a purchase — a local boolean with no receipt
//  behind it, flagged P0 in docs/release/READINESS-AUDIT.md.
//
//  One non-consumable: removing ads. No subscription, no feature gates. See
//  docs/release/MONETIZATION.md.
//

import Foundation
import StoreKit

@MainActor
final class StoreEntitlement: ObservableObject, EntitlementSource {

    static let shared = StoreEntitlement()

    /// Must match the product registered in App Store Connect exactly.
    /// Non-consumable, so it never expires and must be restorable.
    static let removeAdsProductID = "studio.seacloud9.maigexr.removeads"

    // MARK: - Published state

    /// Whether the user owns "Remove Ads".
    @Published private(set) var isEntitled: Bool

    /// The product, once the App Store has described it. Nil until loaded, and
    /// the price string must come from here rather than being hardcoded —
    /// the user's currency and the store's formatting are not ours to guess.
    @Published private(set) var product: Product?

    /// What the purchase UI should currently show.
    @Published private(set) var state: State = .idle

    enum State: Equatable {
        case idle
        case loadingProduct
        case purchasing
        case restoring
        /// Ask to Buy, or a payment awaiting bank approval. Not a failure —
        /// the transaction may complete minutes or days later, and the
        /// `Transaction.updates` listener will catch it.
        case pending
        case failed(String)
    }

    /// Set by `AdManager`, which is the single owner of this callback.
    /// Everything else should observe `isEntitled` through SwiftUI instead.
    var onEntitlementChange: ((Bool) -> Void)?

    // MARK: - Internals

    /// Survives for the life of the app on purpose: a purchase completed on
    /// another device, a refund, or a deferred payment clearing all arrive here
    /// rather than at a call site.
    private var updatesTask: Task<Void, Never>?

    private static let cacheKey = "maigeXR.removeAds.entitled"

    private init() {
        // Cached so the first frame and offline launches are right. Never
        // authoritative: StoreKit overrules this the moment it answers.
        isEntitled = UserDefaults.standard.bool(forKey: Self.cacheKey)
        updatesTask = listenForTransactions()
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Call once at launch. Loads the product and reconciles the cached
    /// entitlement against StoreKit.
    func start() async {
        await refresh()
        await loadProduct()
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? Self.verified(update) else { continue }

                await transaction.finish()
                await self.refresh()
            }
        }
    }

    /// Ask StoreKit what the user actually owns, and record it.
    func refresh() async {
        var entitled = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.verified(result) else { continue }
            guard transaction.productID == Self.removeAdsProductID else { continue }
            // A refunded or revoked purchase is not an entitlement.
            guard transaction.revocationDate == nil else { continue }
            entitled = true
        }

        apply(entitled)
    }

    /// Writes the cache unconditionally, so a revocation clears a stale `true`
    /// rather than leaving it to be believed on the next offline launch.
    private func apply(_ entitled: Bool) {
        UserDefaults.standard.set(entitled, forKey: Self.cacheKey)

        guard entitled != isEntitled else { return }
        isEntitled = entitled
        onEntitlementChange?(entitled)
    }

    // MARK: - Product

    func loadProduct() async {
        guard product == nil else { return }

        state = .loadingProduct
        do {
            let products = try await Product.products(for: [Self.removeAdsProductID])
            product = products.first
            state = product == nil
                ? .failed("That purchase isn’t available right now.")
                : .idle
        } catch {
            state = .failed("Couldn’t reach the App Store. Check your connection and try again.")
        }
    }

    // MARK: - Buying

    func purchase() async {
        if product == nil { await loadProduct() }
        guard let product else { return }

        state = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try Self.verified(verification)
                await transaction.finish()
                await refresh()
                state = .idle

            case .userCancelled:
                // Backing out is not an error and must not show one.
                state = .idle

            case .pending:
                state = .pending

            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed("The purchase didn’t complete. If you were charged, use Restore Purchases.")
        }
    }

    /// Apple requires a visible restore path for a non-consumable.
    func restore() async {
        state = .restoring
        do {
            try await AppStore.sync()
            await refresh()
            state = isEntitled
                ? .idle
                : .failed("No previous purchase found on this Apple Account.")
        } catch {
            // Dismissing the sign-in sheet lands here too, so this is not
            // necessarily worth shouting about. Re-check before deciding.
            await refresh()
            state = isEntitled
                ? .idle
                : .failed("Couldn’t restore purchases. Check your connection and try again.")
        }
    }

    /// Clears a `failed` or `pending` message once the user has seen it.
    func clearStatus() {
        switch state {
        case .failed, .pending: state = .idle
        default: break
        }
    }

    // MARK: - Verification

    /// StoreKit signs every transaction; an unverified one is not trusted.
    private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }
}
