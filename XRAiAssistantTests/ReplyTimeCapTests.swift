import XCTest
@testable import XRAiAssistant

/// A reply that keeps streaming is never "stalled", so it needs an overall cap
/// or a model stuck in a reasoning loop would keep the spinner going.
@MainActor
final class ReplyTimeCapTests: XCTestCase {

    func testRepliesAreCappedOverall() {
        let start = Date()
        XCTAssertFalse(ChatViewModel.hasRunTooLong(startedAt: start, now: start.addingTimeInterval(60)))
        XCTAssertTrue(ChatViewModel.hasRunTooLong(startedAt: start, now: start.addingTimeInterval(ChatViewModel.maxReplyDuration + 1)))
    }

    func testCapIsLongerThanEveryStallLimit() {
        XCTAssertGreaterThan(ChatViewModel.maxReplyDuration, ChatViewModel.silentThinkingTimeout)
        XCTAssertGreaterThan(ChatViewModel.maxReplyDuration, ChatViewModel.inAppStallTimeout)
    }

    func testProviderRetriesAreBounded() {
        XCTAssertLessThanOrEqual(AIRetry.maxAttempts, 3)
        XCTAssertFalse(AIRetry.isTransient(AIProviderHTTPError(provider: "Together.ai", status: 400)),
                       "a refused request is never retried")
    }
}
