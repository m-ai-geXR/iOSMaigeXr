import XCTest
@testable import XRAiAssistant

/// A reply with nothing but reasoning must end in a message, not an empty bubble.
@MainActor
final class EmptyReplyTests: XCTestCase {

    func testReasoningOnlyRepliesAreEmpty() {
        XCTAssertTrue(ChatViewModel.isEmptyReply(""))
        XCTAssertTrue(ChatViewModel.isEmptyReply("<think>planning the island</think>"))
        XCTAssertTrue(ChatViewModel.isEmptyReply("<think>still thinking when the budget ran out"))
        XCTAssertTrue(ChatViewModel.isEmptyReply("  \n"))
    }

    func testAnswersAreNotEmpty() {
        XCTAssertFalse(ChatViewModel.isEmptyReply("<think>plan</think>Here is your scene"))
        XCTAssertFalse(ChatViewModel.isEmptyReply("const cube = 1"))
    }
}

/// GLM thinks and answers from one budget; an empty GLM reply gets one retry at low effort.
@MainActor
final class LowEffortRetryTests: XCTestCase {

    func testGLMEmptyRepliesRetryOnceAtLowEffort() {
        XCTAssertTrue(ChatViewModel.shouldRetryWithLowEffort(model: "zai-org/GLM-5.3", effort: .high, alreadyRetried: false))
        XCTAssertFalse(ChatViewModel.shouldRetryWithLowEffort(model: "zai-org/GLM-5.3", effort: .high, alreadyRetried: true),
                       "only once")
        XCTAssertFalse(ChatViewModel.shouldRetryWithLowEffort(model: "zai-org/GLM-5.3", effort: .medium, alreadyRetried: false),
                       "medium already maps to GLM low")
        XCTAssertFalse(ChatViewModel.shouldRetryWithLowEffort(model: "moonshotai/Kimi-K3", effort: .high, alreadyRetried: false),
                       "only models whose thinking shares the budget")
    }

    func testGLMHasRoomToThinkAndAnswer() {
        let glm = TogetherAIProvider.curatedModels.filter { $0.id.hasPrefix("zai-org/GLM-5.3") }
        XCTAssertEqual(glm.count, 2)
        XCTAssertTrue(glm.allSatisfy { $0.maxOutputTokens >= 65_536 })
    }
}

@MainActor
final class GLMThinkingLimitTests: XCTestCase {
    func testOnlyGLMHasAThinkingLimit() {
        XCTAssertTrue(ChatViewModel.thinksBeforeAnswering("zai-org/GLM-5.3"))
        XCTAssertTrue(ChatViewModel.thinksBeforeAnswering("zai-org/GLM-5.3-Flash"))
        XCTAssertFalse(ChatViewModel.thinksBeforeAnswering("moonshotai/Kimi-K3"))
        XCTAssertFalse(ChatViewModel.thinksBeforeAnswering("claude-opus-5"))
    }

    func testTheLimitLeavesRoomForARetryInsideTheCap() {
        XCTAssertLessThan(ChatViewModel.glmThinkingLimit * 2, ChatViewModel.maxReplyDuration)
    }
}
