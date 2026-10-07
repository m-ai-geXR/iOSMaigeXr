import Foundation
import Security

/// AI provider API keys, held in the iOS Keychain.
///
/// Keys used to live in UserDefaults (a plain plist, included in device backups)
/// and were copied into the SQLite settings table by the first-launch migrator.
/// The Keychain encrypts them, and `ThisDeviceOnly` keeps them out of backups and
/// off other devices. `migrateLegacyStorage()` moves any old keys across once and
/// deletes the plain copies.
enum APIKeyStore {
    /// Every key the app stores. CodeSandbox is optional and not a chat provider;
    /// Local is the optional key for the user's own model server.
    static let providers = ["Together.ai", "OpenAI", "Anthropic", "Google AI", "xAI", "Local", "CodeSandbox"]

    /// Placeholder the app uses to mean "no key". Never written to the Keychain.
    static let unsetValue = "changeMe"

    private static let service = "studio.seacloud9.maigexr.apikeys"

    // MARK: - Read and write

    /// The stored key: the Keychain first, then a fallback copy left in
    /// UserDefaults if a Keychain write ever failed, so no key is silently lost.
    static func key(for provider: String) -> String? {
        if let value = keychainValue(for: provider) { return value }
        return legacyDefaultsNames(for: provider).lazy
            .compactMap { UserDefaults.standard.string(forKey: $0) }
            .first { !$0.isEmpty && $0 != unsetValue }
    }

    private static func keychainValue(for provider: String) -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    /// Stores the key, or removes it when it is empty or the unset placeholder.
    @discardableResult
    static func setKey(_ value: String, for provider: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != unsetValue else {
            return deleteKey(for: provider)
        }
        if writeKeychain(trimmed, for: provider) {
            legacyDefaultsNames(for: provider).forEach { UserDefaults.standard.removeObject(forKey: $0) }
            return true
        }
        // The Keychain refused the write (for example an unsigned build). Keep the
        // key usable rather than drop it; a later successful write moves it in.
        UserDefaults.standard.set(trimmed, forKey: legacyDefaultsNames(for: provider)[0])
        return false
    }

    private static func writeKeychain(_ trimmed: String, for provider: String) -> Bool {
        let data = Data(trimmed.utf8)

        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery(for: provider) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else {
            print("⚠️ Keychain update failed for \(provider): \(status)")
            return false
        }

        var add = baseQuery(for: provider)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("⚠️ Keychain add failed for \(provider): \(addStatus)")
        }
        return addStatus == errSecSuccess
    }

    @discardableResult
    static func deleteKey(for provider: String) -> Bool {
        legacyDefaultsNames(for: provider).forEach { UserDefaults.standard.removeObject(forKey: $0) }
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Migration from plain storage

    /// UserDefaults names that held keys before the Keychain. The legacy single
    /// key was Together.ai's; CodeSandbox had its own name.
    static func legacyDefaultsNames(for provider: String) -> [String] {
        var names = ["XRAiAssistant_APIKey_\(provider)"]
        if provider == "Together.ai" { names.append("XRAiAssistant_APIKey") }
        if provider == "CodeSandbox" { names.append("XRAiAssistant_CodeSandboxAPIKey") }
        return names
    }

    /// Moves keys from UserDefaults into the Keychain, then deletes the plain
    /// copies. A key already in the Keychain wins. Safe to call on every launch.
    static func migrateLegacyStorage(defaults: UserDefaults = .standard) {
        var moved = 0
        for provider in providers {
            let names = legacyDefaultsNames(for: provider)
            let legacy = names.lazy
                .compactMap { defaults.string(forKey: $0) }
                .first { !$0.isEmpty && $0 != unsetValue }

            if keychainValue(for: provider) == nil, let legacy, writeKeychain(legacy, for: provider) {
                moved += 1
            }
            // Clear the plain copies only once the Keychain holds the key, or when
            // there was nothing worth keeping, so a failed write loses nothing.
            if keychainValue(for: provider) != nil || legacy == nil {
                names.forEach { defaults.removeObject(forKey: $0) }
            }
        }
        if moved > 0 { print("🔐 Moved \(moved) API key(s) into the Keychain") }
    }

    /// SQLite settings rows that may hold copies made by the old migrator.
    static let legacySQLiteKeyPrefix = "XRAiAssistant_APIKey"

    // MARK: - Helpers

    private static func baseQuery(for provider: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider
        ]
    }
}
