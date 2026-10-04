import XCTest
import SwiftUI
@testable import XRAiAssistant

/// Renders a chat bubble to a PNG so the wrapping fix can be checked visually,
/// and asserts the shape of the result: a paragraph that wraps across the full
/// bubble is tall-and-full-width, whereas the old HStack layout squeezed the
/// text into a narrow column and produced a much taller image.
@MainActor
final class MarkdownBubbleSnapshotTests: XCTestCase {

    private let bubbleWidth: CGFloat = 320

    private var outputDirectory: URL {
        // Defaults to the simulator's own tmp. To collect the PNGs on the host,
        // point SNAPSHOT_DIR at a writable absolute path:
        // (xcodebuild only forwards host env vars to the test runner when they
        // carry the TEST_RUNNER_ prefix):
        //   TEST_RUNNER_SNAPSHOT_DIR=/tmp/maigexr-snapshots xcodebuild test ... \
        //     -only-testing:XRAiAssistantTests/MarkdownBubbleSnapshotTests
        let path = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return URL(fileURLWithPath: path)
    }

    private func render(_ content: String, isUser: Bool, named name: String) -> CGSize {
        let view = MarkdownMessageView(content: content, isUser: isUser)
            .padding(12)
            .frame(width: bubbleWidth)
            .background(isUser ? Color.blue : Color(.systemGray5))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        guard let image = renderer.uiImage else {
            XCTFail("ImageRenderer produced no image for \(name)")
            return .zero
        }

        if let data = image.pngData() {
            let url = outputDirectory.appendingPathComponent("\(name).png")
            try? data.write(to: url)
            print("SNAPSHOT \(name): \(url.path) size=\(image.size)")
        }

        return image.size
    }

    func testReportedParagraphWrapsAcrossTheFullBubble() {
        let content = """
        Create **AFTERGLOW EXPRESS**, a playable NOVA64 showcase where a tiny futuristic train races along a floating railway through a midnight ocean of clouds.

        - Bloom on windows, stars, track lights, and jellyfish, with controlled highlights that preserve detail.

        The signature moment is an **Afterglow Pulse**: the player sends a luminous wave through the world.

        Use `nova64.fx.enableBloom()` to switch it on.
        """

        let size = render(content, isUser: true, named: "user-bubble")

        XCTAssertEqual(size.width, bubbleWidth, accuracy: 1.0,
                       "the bubble should occupy the width it was given")

        // The three paragraphs plus a bullet and a code line wrap to roughly a
        // dozen lines at this width. The old narrow-column layout pushed this
        // well past 400pt. Generous bounds: this is a shape check, not a pixel test.
        XCTAssertLessThan(size.height, 400,
                          "text is wrapping into a narrow column instead of flowing across the bubble")
        XCTAssertGreaterThan(size.height, 120,
                             "suspiciously short - the content probably did not render")
    }

    func testAssistantBubbleRendersForComparison() {
        let content = "Here is **bold** text followed by a long explanatory sentence that must wrap naturally across the whole width of the assistant bubble rather than stacking into a column."
        let size = render(content, isUser: false, named: "assistant-bubble")
        XCTAssertEqual(size.width, bubbleWidth, accuracy: 1.0)
        XCTAssertLessThan(size.height, 250)
    }
}
