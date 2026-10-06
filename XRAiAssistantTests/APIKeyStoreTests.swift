import XCTest
@testable import XRAiAssistant

/// API keys must live in the Keychain, and old plain copies must be moved there
/// and removed. The Keychain needs a signed test host: run these with simulator
/// signing enabled (the default in Xcode), not CODE_SIGNING_ALLOWED=NO.
final class APIKeyStoreTests: XCTestCase {

    private let provider = "Together.ai"
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "APIKeyStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        APIKeyStore.deleteKey(for: provider)
    }

    override func tearDown() {
        APIKeyStore.deleteKey(for: provider)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRoundTrip() {
        XCTAssertTrue(APIKeyStore.setKey("tk-test-123", for: provider))
        XCTAssertEqual(APIKeyStore.key(for: provider), "tk-test-123")

        XCTAssertTrue(APIKeyStore.setKey("tk-test-456", for: provider), "updating an existing key")
        XCTAssertEqual(APIKeyStore.key(for: provider), "tk-test-456")
    }

    func testEmptyOrPlaceholderRemovesTheKey() {
        APIKeyStore.setKey("tk-test-123", for: provider)
        APIKeyStore.setKey(APIKeyStore.unsetValue, for: provider)
        XCTAssertNil(APIKeyStore.key(for: provider))

        APIKeyStore.setKey("tk-test-123", for: provider)
        APIKeyStore.setKey("   ", for: provider)
        XCTAssertNil(APIKeyStore.key(for: provider))
    }

    func testMigrationMovesThePlainCopyAndDeletesIt() {
        defaults.set("tk-legacy", forKey: "XRAiAssistant_APIKey")

        APIKeyStore.migrateLegacyStorage(defaults: defaults)

        XCTAssertEqual(APIKeyStore.key(for: provider), "tk-legacy")
        XCTAssertNil(defaults.string(forKey: "XRAiAssistant_APIKey"), "plain copy must be removed")
        XCTAssertNil(defaults.string(forKey: "XRAiAssistant_APIKey_Together.ai"))
    }

    func testMigrationKeepsAKeyAlreadyInTheKeychain() {
        APIKeyStore.setKey("tk-current", for: provider)
        defaults.set("tk-stale", forKey: "XRAiAssistant_APIKey_Together.ai")

        APIKeyStore.migrateLegacyStorage(defaults: defaults)

        XCTAssertEqual(APIKeyStore.key(for: provider), "tk-current")
        XCTAssertNil(defaults.string(forKey: "XRAiAssistant_APIKey_Together.ai"))
    }

    func testMigrationDropsThePlaceholder() {
        defaults.set(APIKeyStore.unsetValue, forKey: "XRAiAssistant_APIKey_Together.ai")

        APIKeyStore.migrateLegacyStorage(defaults: defaults)

        XCTAssertNil(APIKeyStore.key(for: provider))
        XCTAssertNil(defaults.string(forKey: "XRAiAssistant_APIKey_Together.ai"))
    }
}
