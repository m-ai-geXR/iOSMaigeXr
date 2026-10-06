import SwiftUI

@main
struct XRAiAssistant: App {
    @State private var showSplash = true
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
        }
    }

    /// Entitlement first, then consent, then ads.
    ///
    /// The order matters: a user who has paid is never shown a consent form for
    /// ads they will not be served. For them consent stays `.unknown` — we did
    /// not ask, which is not the same as being refused.
    @MainActor
    private func startMonetization() async {
        await StoreEntitlement.shared.start()

        guard AppConfig.adsEnabled, !StoreEntitlement.shared.isEntitled else {
            await AdManager.shared.start(consent: .unknown)
            return
        }

        let consent = await AdConsentStore.shared.resolve()
        await AdManager.shared.start(consent: consent)
    }
}