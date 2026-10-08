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
