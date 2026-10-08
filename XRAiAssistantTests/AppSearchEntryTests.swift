import XCTest
@testable import XRAiAssistant

/// Device search must find the app by "maigexr", without the braces in its name.
final class AppSearchEntryTests: XCTestCase {
    func testPlainNameIsAKeyword() {
        XCTAssertTrue(AppSearchEntry.keywords.contains("maigexr"))
        XCTAssertTrue(AppSearchEntry.keywords.contains("maige"))
        XCTAssertTrue(AppSearchEntry.keywords.allSatisfy { $0 == $0.lowercased() })
    }
}
