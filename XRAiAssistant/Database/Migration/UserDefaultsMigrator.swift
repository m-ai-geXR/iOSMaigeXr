//
//  UserDefaultsMigrator.swift
//  XRAiAssistant
//
//  Handles one-time migration from UserDefaults to SQLite database
//

import Foundation

@MainActor
class UserDefaultsMigrator {
    private let db = DatabaseManager.shared
    private let migrationCompleteKey = "XRAiAssistant_SQLiteMigrationComplete"
    private let migrationVersionKey = "XRAiAssistant_SQLiteMigrationVersion"
    private let currentMigrationVersion = 1

    func shouldMigrate() -> Bool {
        let isComplete = UserDefaults.standard.bool(forKey: migrationCompleteKey)
        let version = UserDefaults.standard.integer(forKey: migrationVersionKey)
        return !isComplete || version < currentMigrationVersion
    }

    func migrateToSQLite() async throws {
        print("🔄 Starting migration from UserDefaults to SQLite...")
        print("📊 Migration version: \(currentMigrationVersion)")

        do {
            // 1. Migrate settings
            try await migrateSettings()

            // 2. Migrate API keys (to SQLite for now, will move to Keychain in Phase 3)
            try await migrateAPIKeys()

            // 3. Migrate conversations
            try await migrateConversations()

            // 4. Mark migration complete
            UserDefaults.standard.set(true, forKey: migrationCompleteKey)
            UserDefaults.standard.set(currentMigrationVersion, forKey: migrationVersionKey)

            print("✅ Migration complete!")
            print("💾 Total migrated data saved to SQLite")

        } catch {
            print("❌ Migration failed: \(error)")
            throw MigrationError.migrationFailed(error)
        }
    }

    // MARK: - Settings Migration

    private func migrateSettings() async throws {
        print("📝 Migrating settings...")

        let keysToMigrate: [(key: String, defaultValue: Any?)] = [
            ("XRAiAssistant_SystemPrompt", nil),
            ("XRAiAssistant_SelectedModel", nil),
            ("XRAiAssistant_Temperature", 0.7),
            ("XRAiAssistant_TopP", 0.9),
            ("XRAiAssistant_APIKey", "changeMe") // Legacy key
        ]

        var migratedCount = 0

        for (key, defaultValue) in keysToMigrate {
            if let value = UserDefaults.standard.object(forKey: key) {
                try await db.saveSetting(key: key, value: value)
                print("  ✅ Migrated: \(key)")
                migratedCount += 1
            } else if let defaultValue = defaultValue {
                // Save default value if setting doesn't exist
                try await db.saveSetting(key: key, value: defaultValue)
                print("  ℹ️ Set default: \(key) = \(defaultValue)")
                migratedCount += 1
            }
        }

        print("  📊 Migrated \(migratedCount) settings")
    }

    // MARK: - API Keys Migration

    private func migrateAPIKeys() async throws {
        print("🔑 Migrating API keys...")

        let providers = [
            "Together.ai",
            "Google AI",
            "Anthropic",
            "OpenAI",
            "CodeSandbox"
        ]

        var migratedCount = 0

        // Check legacy API key first
        if let legacyKey = UserDefaults.standard.string(forKey: "XRAiAssistant_APIKey"),
           legacyKey != "changeMe" {
            try await db.saveSetting(key: "XRAiAssistant_APIKey_Together.ai", value: legacyKey)
            print("  ✅ Migrated legacy API key to Together.ai")
            migratedCount += 1
        }

        // Migrate provider-specific keys
        for provider in providers {
            let key = "XRAiAssistant_APIKey_\(provider)"
            if let apiKey = UserDefaults.standard.string(forKey: key) {
                // For now, save to SQLite. In Phase 3, we'll move to iOS Keychain
                try await db.saveSetting(key: key, value: apiKey)
                print("  ✅ Migrated API key for: \(provider)")
                migratedCount += 1
            }
        }

        print("  📊 Migrated \(migratedCount) API keys")
    }

    // MARK: - Conversations Migration

    private func migrateConversations() async throws {
        print("💬 Migrating conversations...")

        guard let data = UserDefaults.standard.data(forKey: "XRAiAssistant_Conversations") else {
            print("  ℹ️ No conversations to migrate")
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let conversations = try decoder.decode([Conversation].self, from: data)

            print("  📦 Found \(conversations.count) conversations to migrate")

            var successCount = 0
            var failureCount = 0

            for (index, conversation) in conversations.enumerated() {
                do {
                    try await db.saveConversation(conversation)
                    print("  ✅ Migrated conversation \(index + 1)/\(conversations.count): \(conversation.title.prefix(40))...")
                    successCount += 1
                } catch {
                    print("  ❌ Failed to migrate conversation \(index + 1): \(error)")
                    failureCount += 1
                }
            }

            print("  📊 Migration complete: \(successCount) succeeded, \(failureCount) failed")

            if successCount > 0 {
                print("  💾 Successfully migrated \(successCount) conversations to SQLite")
            }

        } catch {
            print("  ❌ Failed to decode conversations: \(error)")
            throw MigrationError.decodingFailed(error)
        }
    }

    // MARK: - Cleanup (optional - use with caution)

    func cleanupUserDefaults() {
        print("🧹 Cleaning up UserDefaults (removing migrated data)...")

        let keysToRemove = [
            "XRAiAssistant_SystemPrompt",
            "XRAiAssistant_SelectedModel",
            "XRAiAssistant_Temperature",
            "XRAiAssistant_TopP",
            "XRAiAssistant_APIKey",
            "XRAiAssistant_Conversations"
        ]

        for key in keysToRemove {
            UserDefaults.standard.removeObject(forKey: key)
        }

        print("✅ UserDefaults cleanup complete")
    }

    // MARK: - Rollback (for debugging/testing)

    func rollbackMigration() {
        print("⚠️ Rolling back migration...")
        UserDefaults.standard.set(false, forKey: migrationCompleteKey)
        UserDefaults.standard.set(0, forKey: migrationVersionKey)
        print("✅ Migration rolled back - will run again on next launch")
    }
}

// MARK: - Migration Errors

enum MigrationError: Error, LocalizedError {
    case migrationFailed(Error)
    case decodingFailed(Error)
    case databaseError(Error)

    var errorDescription: String? {
        switch self {
        case .migrationFailed(let error):
            return "Migration failed: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode UserDefaults data: \(error.localizedDescription)"
        case .databaseError(let error):
            return "Database error during migration: \(error.localizedDescription)"
        }
    }
}
