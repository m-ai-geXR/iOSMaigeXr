import XCTest
@testable import XRAiAssistant

/// GLM and Kimi stream their reasoning with no `content` for a long time. The
/// app must treat that as progress, not a dead connection, and refused
/// requests must never be reported as "No connection".
final class TogetherStreamTests: XCTestCase {

    func testReasoningIsWrappedAsThinkingThenAnswer() {
        var parser = TogetherAIProvider.StreamParser()
        let lines = [
            #"data: {"choices":[{"delta":{"role":"assistant","content":null,"reasoning":"Plan "}}]}"#,
            #"data: {"choices":[{"delta":{"reasoning":"the cube"}}]}"#,
            ": keep-alive",
            #"data: {"choices":[{"delta":{"content":"const cube"}}]}"#,
            #"data: {"choices":[{"delta":{"content":" = 1"}}],"usage":null}"#
        ]
        let raw = lines.compactMap { parser.text(fromLine: $0) }.joined() + (parser.finish() ?? "")
        XCTAssertEqual(raw, "<think>Plan the cube</think>const cube = 1")
        XCTAssertEqual(ReplyText.visible(raw).text, "const cube = 1")

        var thinking = TogetherAIProvider.StreamParser()
        let partial = thinking.text(fromLine: lines[0]) ?? ""
        XCTAssertTrue(ReplyText.visible(partial).isThinking, "shown as Thinking while it reasons")
    }

    func testRefusedRequestsAreNotReportedAsOffline() {
        let refused = AIErrorClassifier.classify(AIProviderError.networkError("HTTP 400: {\"error\":\"bad\"}"), provider: "OpenAI")
        XCTAssertNotEqual(refused.category, .offline)
        XCTAssertEqual(refused.category, .invalidRequest)

        let busy = AIErrorClassifier.classify(AIProviderError.networkError("HTTP 503: overloaded"), provider: "xAI")
        XCTAssertEqual(busy.category, .serverError)
    }

    func testRateLimitsAndServerErrorsAreRetried() {
        XCTAssertTrue(AIRetry.isTransient(AIProviderHTTPError(provider: "Together.ai", status: 503)))
        XCTAssertTrue(AIRetry.isTransient(AIProviderHTTPError(provider: "Together.ai", status: 429)))
        XCTAssertFalse(AIRetry.isTransient(AIProviderHTTPError(provider: "Together.ai", status: 400)))
    }
}
