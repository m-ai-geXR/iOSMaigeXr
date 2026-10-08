import XCTest
@testable import XRAiAssistant

/// A real GLM-5.3 stream from Together (captured 2026-10-08): reasoning in
/// `reasoning_content`, then the answer in `content`. The app must end up with
/// the answer, not "No answer".
@MainActor
final class GLMRealStreamTests: XCTestCase {

    private func lines() throws -> [String] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/glm-stream.txt")
        return try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
    }

    func testRealGLMStreamYieldsTheAnswer() throws {
        var parser = TogetherAIProvider.StreamParser()
        var raw = ""
        for line in try lines() {
            if line.trimmingCharacters(in: .whitespaces) == "data: [DONE]" { break }
            if let text = parser.text(fromLine: line) { raw += text }
        }
        raw += parser.finish() ?? ""
        let visible = ReplyText.visible(raw).text
        XCTAssertFalse(ChatViewModel.isEmptyReply(raw), "GLM answered; the app must not say No answer")
        XCTAssertTrue(visible.contains("nova64"), "the scene code is in the visible answer")
        XCTAssertFalse(visible.contains("The user wants"), "reasoning is hidden")
    }
}
