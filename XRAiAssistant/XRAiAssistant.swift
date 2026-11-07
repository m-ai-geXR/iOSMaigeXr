import SwiftUI

@main
struct XRAiAssistant: App {
    /// Finishes AI replies in the background when the user leaves the app.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var isStartingMonetization = false
    @State private var monetizationResolved = false
    @StateObject private var appearanceStore = AppearanceStore.shared

    init() {
        // Run database migration on first launch
        Task {
            let migrator = UserDefaultsMigrator()
            if migrator.shouldMigrate() {
                print("🔄 Starting UserDefaults → SQLite migration...")
                do {
                    try await migrator.migrateToSQLite()
                    print("✅ Migration completed successfully!")
                } catch {
                    print("❌ Migration failed: \(error)")
                    // App will fall back to UserDefaults if needed
                }
            } else {
                print("✅ Database already migrated to SQLite")
            }

            // API keys belong in the Keychain. Remove any copies the migrator
            // wrote to SQLite before that change; harmless when there are none.
            try? await DatabaseManager.shared.deleteSettings(withPrefix: APIKeyStore.legacySQLiteKeyPrefix)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main app (hidden behind splash initially)
                ContentView()
                    .opacity(showSplash ? 0 : 1)

                // Splash screen overlay
                if showSplash {
                    SplashScreenView {
                        withAnimation(.easeOut(duration: 0.6)) {
                            showSplash = false
                        }
                        // Only once the real UI is up: both the consent form and
                        // the ATT prompt are system sheets, and presenting them
                        // over the splash means presenting them over nothing.
                        Task { await startMonetization() }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            // One place decides the window's scheme. nil follows the system.
            .preferredColorScheme(appearanceStore.appearance.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && !showSplash {
                    Task { await startMonetization() }
                }
            }
        }
    }

    /// Entitlement first, then consent, then ads.
    ///
    /// The order matters: a user who has paid is never shown a consent form for
    /// ads they will not be served. For them consent stays `.unknown` — we did
    /// not ask, which is not the same as being refused.
    @MainActor
    private func startMonetization() async {
        guard !isStartingMonetization else { return }
        isStartingMonetization = true
        defer { isStartingMonetization = false }

        if monetizationResolved {
            // System Settings can change ATT while the app is backgrounded.
            // Discard ads prepared under an authorization the user revoked.
            await AdConsentStore.shared.refreshAfterPrivacyOptionsChange()
            let consent = AdConsentStore.shared.consent
            await AdManager.shared.updateConsent(consent)
            if consent != .unknown { return }
            monetizationResolved = false
        }

        await StoreEntitlement.shared.refresh()
        // Product pricing is independent of entitlement and must not delay
        // the consent prompt when the App Store is slow or unavailable.
        Task { await StoreEntitlement.shared.loadProduct() }

        guard AppConfig.adsEnabled, !StoreEntitlement.shared.isEntitled else {
            await AdManager.shared.start(consent: .unknown)
            monetizationResolved = true
            return
        }

        let consent = await AdConsentStore.shared.resolve()
        await AdManager.shared.start(consent: consent)
        // Retry an interrupted request or failed UMP update on next foreground.
        monetizationResolved = consent != .unknown
    }
}
