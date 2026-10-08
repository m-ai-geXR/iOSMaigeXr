import XCTest
@testable import XRAiAssistant

/// Reasoning models put their thinking in <think>…</think>; only the answer is shown.
final class ReplyTextTests: XCTestCase {

    func testFinishedThinkingIsRemoved() {
        let shown = ReplyText.visible("<think>plan the cube</think>\nHere is your cube.")
        XCTAssertEqual(shown.text, "Here is your cube.")
        XCTAssertFalse(shown.isThinking)
    }

    func testUnfinishedThinkingShowsThinking() {
        let shown = ReplyText.visible("<think>still planning the")
        XCTAssertEqual(shown.text, "")
        XCTAssertTrue(shown.isThinking)
    }

    func testClosingTagWithoutOpeningIsHandled() {
        XCTAssertEqual(ReplyText.visible("planning…</think>Answer").text, "Answer")
    }

    func testPlainRepliesAreUntouched() {
        let reply = "Here is code:\n```js\nconst a = 1 < 2;\n```"
        XCTAssertEqual(ReplyText.visible(reply).text, reply)
        XCTAssertFalse(ReplyText.visible(reply).isThinking)
    }
}
