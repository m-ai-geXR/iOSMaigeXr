import SwiftUI

@main
struct XRAiAssistant: App {
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
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}