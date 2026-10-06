import XCTest
@testable import XRAiAssistant

/// Mirrors Android's FavoriteTitleTest and MessagePreviewTest, so both apps name
/// scenes the same way.
final class SceneTextTests: XCTestCase {

    func testUsesTheMarkdownHeading() {
        let reply = "## The Lantern Sea\n\nAn asset-free voyage.\n\n[INSERT_CODE]```javascript\nlet S, G, H;\n```"
        XCTAssertEqual(SceneText.title(fromReply: reply), "The Lantern Sea")
    }

    func testUsesABoldLeadWhenThereIsNoHeading() {
        let reply = "**Follow the storm.** A four-minute journey.\n```js\nlet S;\n```"
        XCTAssertEqual(SceneText.title(fromReply: reply), "Follow the storm")
    }

    func testReturnsNilWhenTheReplyNamesNothing() {
        XCTAssertNil(SceneText.title(fromReply: "Here is your scene.\n```js\nx\n```"))
    }

    func testCodeFallbackSkipsBlankAndCommentLines() {
        XCTAssertEqual(SceneText.title(fromCode: "\n// cart\n/* x */\n  let cubes = [];"), "let cubes = [];")
    }

    func testPreviewDropsCodeAndMarkdown() {
        let reply = "## The Lantern Sea\n\nAn **asset-free** voyage. Press `N`.\n```js\nlet S;\n```"
        XCTAssertEqual(SceneText.preview(of: reply), "The Lantern Sea An asset-free voyage. Press N.")
    }

    func testPreviewDoesNotRepeatTheTitle() {
        let reply = "## The Lantern Sea\n\nAn asset-free voyage.\n```js\nlet S;\n```"
        XCTAssertEqual(SceneText.preview(of: reply, droppingTitle: "The Lantern Sea"), "An asset-free voyage.")
    }

    func testLegacyTitleMatchesTheOldRule() {
        XCTAssertEqual(SceneText.legacyTitle(fromCode: "// NOVA64: BOARDWALK\nlet C, G;"), "let C, G;")
    }
}
