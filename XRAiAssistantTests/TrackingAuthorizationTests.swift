import AppTrackingTransparency
import XCTest
@testable import XRAiAssistant

@MainActor
final class TrackingAuthorizationTests: XCTestCase {
    func testExistingDecisionsNeverRequestAnotherPrompt() async throws {
        for status in [ATTrackingManager.AuthorizationStatus.authorized, .denied, .restricted] {
            let resolver = TrackingAuthorizationResolver(
                status: { status },
                request: { XCTFail("must respect the existing decision"); return .notDetermined },
                waitUntilReady: { XCTFail("no presentation needed") }
            )
            let result = try await resolver.resolve()
            XCTAssertEqual(result, status)
        }
    }

    func testInterruptedPromptRetriesAfterWaitingForPresentationAgain() async throws {
        var requests = 0
        var waits = 0
        let resolver = TrackingAuthorizationResolver(
            status: { .notDetermined },
            request: {
                requests += 1
                XCTAssertEqual(waits, requests)
                return requests == 1 ? .notDetermined : .authorized
            },
            waitUntilReady: { waits += 1 }
        )
        let result = try await resolver.resolve()
        XCTAssertEqual(result, .authorized)
        XCTAssertEqual(requests, 2)
    }

    func testRepeatedPresentationFailureStaysUndeterminedAndDoesNotLoop() async throws {
        var requests = 0
        let resolver = TrackingAuthorizationResolver(
            status: { .notDetermined },
            request: { requests += 1; return .notDetermined },
            waitUntilReady: {}
        )
        let result = try await resolver.resolve()
        XCTAssertEqual(result, .notDetermined)
        XCTAssertEqual(requests, 2)
    }

    func testDenialDoesNotTriggerARetry() async throws {
        var requests = 0
        let resolver = TrackingAuthorizationResolver(
            status: { .notDetermined },
            request: { requests += 1; return .denied },
            waitUntilReady: {}
        )
        let result = try await resolver.resolve()
        XCTAssertEqual(result, .denied)
        XCTAssertEqual(requests, 1)
    }

    func testDecisionObtainedWhileWaitingDoesNotPromptAgain() async throws {
        var status = ATTrackingManager.AuthorizationStatus.notDetermined
        let resolver = TrackingAuthorizationResolver(
            status: { status },
            request: { XCTFail("another consent flow already resolved ATT"); return .notDetermined },
            waitUntilReady: { status = .authorized }
        )
        let result = try await resolver.resolve()
        XCTAssertEqual(result, .authorized)
    }

    func testCancelledPresentationDoesNotRequestPermission() async {
        let resolver = TrackingAuthorizationResolver(
            status: { .notDetermined },
            request: { XCTFail("must not present after cancellation"); return .authorized },
            waitUntilReady: { throw CancellationError() }
        )
        do {
            _ = try await resolver.resolve()
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
