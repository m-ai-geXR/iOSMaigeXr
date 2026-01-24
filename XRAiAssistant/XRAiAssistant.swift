import SwiftUI

@main
struct XRAiAssistant: App {
    @State private var showSplash = true

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
                    .preferredColorScheme(.dark)
                    .opacity(showSplash ? 0 : 1)

                // Splash screen overlay
                if showSplash {
                    SplashScreenView {
                        withAnimation(.easeOut(duration: 0.6)) {
                            showSplash = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
        }
    }
}