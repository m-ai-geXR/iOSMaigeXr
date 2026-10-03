import XCTest
import SwiftUI
@testable import XRAiAssistant

/// Regression tests for the chat bubble wrapping bug.
///
/// A line with inline formatting used to be composed from several side-by-side
/// `Text` views in an `HStack`, which gave each run its own column: the long run
/// after a short `**bold**` run wrapped inside a narrow column on the right
/// instead of flowing across the bubble. The fix emits one `AttributedString`.
///
/// Layout itself is not unit-testable here, so these lock down the thing that
/// made the layout wrong: the line must survive as a single contiguous string
/// with the markers removed and the runs carrying the right attributes.
final class MarkdownInlineRendererTests: XCTestCase {

    // The paragraph from the bug report that wrapped into a narrow column.
    private let reportedLine = "Create **AFTERGLOW EXPRESS**, a playable NOVA64 showcase where a tiny futuristic train races along a floating railway through a midnight ocean of clouds."

    // MARK: - The line survives as one flowing string

    func testBoldLineProducesOneContiguousStringWithMarkersRemoved() {
        let attributed = MarkdownInlineRenderer.attributedString(for: reportedLine, isUser: true)

        XCTAssertEqual(
            String(attributed.characters),
            "Create AFTERGLOW EXPRESS, a playable NOVA64 showcase where a tiny futuristic train races along a floating railway through a midnight ocean of clouds.",
            "The bold markers should be gone and the rest of the line must stay contiguous; if the tail is split or dropped the bubble wraps wrongly."
        )
    }

    func testLongTailAfterBoldStaysInASingleRun() {
        let blocks = MarkdownInlineRenderer.parse(reportedLine)

        // plain "Create ", bold "AFTERGLOW EXPRESS", then the whole remainder.
        XCTAssertEqual(blocks.count, 3)

        guard case .plainText(let lead) = blocks[0] else { return XCTFail("expected leading plain text") }
        guard case .boldText(let bold) = blocks[1] else { return XCTFail("expected bold run") }
        guard case .plainText(let tail) = blocks[2] else { return XCTFail("expected trailing plain text") }

        XCTAssertEqual(lead, "Create ")
        XCTAssertEqual(bold, "AFTERGLOW EXPRESS")
        XCTAssertTrue(tail.hasPrefix(", a playable NOVA64 showcase"))
        XCTAssertTrue(tail.hasSuffix("midnight ocean of clouds."))
    }

    func testSecondReportedParagraphRoundTrips() {
        let line = "The signature moment is an **Afterglow Pulse**: the player sends a luminous wave through the world."
        let attributed = MarkdownInlineRenderer.attributedString(for: line, isUser: true)

        XCTAssertEqual(
            String(attributed.characters),
            "The signature moment is an Afterglow Pulse: the player sends a luminous wave through the world."
        )
    }

    // MARK: - Attributes

    func testBoldRunIsBoldAndRestIsNot() {
        let attributed = MarkdownInlineRenderer.attributedString(for: "plain **bold** plain", isUser: false)

        var sawBold = false
        var sawBody = false
        for run in attributed.runs {
            let slice = String(attributed[run.range].characters)
            if slice == "bold" {
                sawBold = true
                XCTAssertEqual(run.font, Font.body.bold())
            } else if slice.contains("plain") {
                sawBody = true
                XCTAssertEqual(run.font, Font.body)
            }
        }
        XCTAssertTrue(sawBold, "expected a bold run")
        XCTAssertTrue(sawBody, "expected unstyled body runs around it")
    }

    func testUserTextIsWhiteAndAssistantTextIsPrimary() {
        let user = MarkdownInlineRenderer.attributedString(for: "**hi** there", isUser: true)
        for run in user.runs {
            XCTAssertEqual(run.foregroundColor, Color.white, "outgoing bubble text must stay white on blue")
        }

        let assistant = MarkdownInlineRenderer.attributedString(for: "**hi** there", isUser: false)
        for run in assistant.runs {
            XCTAssertEqual(run.foregroundColor, Color.primary)
        }
    }

    func testInlineCodeGetsMonospacedFontAndBackground() {
        let attributed = MarkdownInlineRenderer.attributedString(for: "call `runCode()` now", isUser: false)

        let codeRun = attributed.runs.first { String(attributed[$0.range].characters).contains("runCode()") }
        XCTAssertNotNil(codeRun, "expected an inline code run")
        XCTAssertEqual(codeRun?.font, Font.system(.body, design: .monospaced))
        XCTAssertNotNil(codeRun?.backgroundColor, "inline code should be tinted")
    }

    func testInlineCodeIsReadableOnTheBlueBubble() {
        let attributed = MarkdownInlineRenderer.attributedString(for: "call `runCode()`", isUser: true)
        let codeRun = attributed.runs.first { String(attributed[$0.range].characters).contains("runCode()") }
        XCTAssertEqual(codeRun?.foregroundColor, Color.white,
                       "dark code text on the blue outgoing bubble is unreadable")
    }

    // MARK: - Parsing edge cases

    func testPlainLineIsASingleRun() {
        let blocks = MarkdownInlineRenderer.parse("no formatting at all here")
        XCTAssertEqual(blocks.count, 1)
        guard case .plainText(let t) = blocks[0] else { return XCTFail("expected plain text") }
        XCTAssertEqual(t, "no formatting at all here")
    }

    func testItalicIsParsed() {
        let blocks = MarkdownInlineRenderer.parse("some *emphasis* here")
        XCTAssertEqual(blocks.count, 3)
        guard case .italicText(let t) = blocks[1] else { return XCTFail("expected italic run") }
        XCTAssertEqual(t, "emphasis")
    }

    func testUnterminatedBoldKeepsTheRestOfTheLine() {
        // Regression: an unterminated ** used to swallow the tail of the line.
        let line = "a **dangling bold marker and then more words"
        let attributed = MarkdownInlineRenderer.attributedString(for: line, isUser: false)
        XCTAssertEqual(String(attributed.characters), line,
                       "an unclosed marker must render literally, losing no text")
    }

    func testUnterminatedInlineCodeKeepsTheRestOfTheLine() {
        let line = "a `dangling code marker and then more words"
        let attributed = MarkdownInlineRenderer.attributedString(for: line, isUser: false)
        XCTAssertEqual(String(attributed.characters), line)
    }

    func testMultipleBoldRunsOnOneLine() {
        let attributed = MarkdownInlineRenderer.attributedString(for: "**one** and **two**", isUser: false)
        XCTAssertEqual(String(attributed.characters), "one and two")

        let boldSlices = attributed.runs
            .filter { $0.font == Font.body.bold() }
            .map { String(attributed[$0.range].characters) }
        XCTAssertEqual(boldSlices, ["one", "two"])
    }

    func testBoldAdjacentToPunctuationRoundTrips() {
        let attributed = MarkdownInlineRenderer.attributedString(for: "(**bold**), done", isUser: false)
        XCTAssertEqual(String(attributed.characters), "(bold), done")
    }

    func testEmptyLineProducesNoRuns() {
        XCTAssertTrue(MarkdownInlineRenderer.parse("").isEmpty)
    }
}
