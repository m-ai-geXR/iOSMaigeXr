import XCTest
@testable import XRAiAssistant

/// Guards the fix for replies failing with "network connection lost" when the
/// user leaves the app mid-request: the request must hold a background task,
/// connection drops must be recognised, and the request must be sent again.
@MainActor
final class BackgroundRequestTests: XCTestCase {

    private final class FakeHost: BackgroundTaskHosting {
        var begun = 0
        var ended: [UIBackgroundTaskIdentifier] = []
        var expire: (() -> Void)?

        func begin(name: String, onExpire: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
            begun += 1
            expire = onExpire
            return UIBackgroundTaskIdentifier(rawValue: 42)
        }

        func end(_ identifier: UIBackgroundTaskIdentifier) {
            ended.append(identifier)
        }
    }

    private struct Failure: Error {}

    // MARK: - Background task

    func testTaskEndsAfterSuccess() async throws {
        let host = FakeHost()
        let value = await BackgroundRequest.run("test", host: host) { 7 }
        XCTAssertEqual(value, 7)
        XCTAssertEqual(host.begun, 1)
        XCTAssertEqual(host.ended, [UIBackgroundTaskIdentifier(rawValue: 42)])
    }

    func testTaskEndsAfterFailure() async {
        let host = FakeHost()
        do {
            _ = try await BackgroundRequest.run("test", host: host) { () async throws -> Int in throw Failure() }
            XCTFail("expected the error to propagate")
        } catch {}
        XCTAssertEqual(host.ended.count, 1)
    }

    func testExpiryEndsTaskOnceOnly() async {
        let host = FakeHost()
        _ = await BackgroundRequest.run("test", host: host) { () async -> Int in
            host.expire?()   // the system runs out of time mid-request
            return 1
        }
        XCTAssertEqual(host.ended.count, 1, "expiry and completion must not both end the task")
    }

    // MARK: - Recognising a dropped connection

    func testConnectionDropsAreInterruptions() {
        for code: URLError.Code in [.networkConnectionLost, .notConnectedToInternet, .timedOut,
                                    .cannotConnectToHost, .backgroundSessionWasDisconnected] {
            XCTAssertTrue(BackgroundRequest.isInterruption(URLError(code)), "\(code.rawValue)")
        }
    }

    func testWrappedConnectionDropIsInterruption() {
        let wrapped = NSError(domain: "Provider", code: 1,
                              userInfo: [NSUnderlyingErrorKey: URLError(.networkConnectionLost)])
        XCTAssertTrue(BackgroundRequest.isInterruption(wrapped))
        let described = NSError(domain: "Provider", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "The network connection was lost."])
        XCTAssertTrue(BackgroundRequest.isInterruption(described))
    }

    func testRealErrorsAreNotInterruptions() {
        XCTAssertFalse(BackgroundRequest.isInterruption(URLError(.badServerResponse)))
        XCTAssertFalse(BackgroundRequest.isInterruption(URLError(.userAuthenticationRequired)))
        XCTAssertFalse(BackgroundRequest.isInterruption(Failure()))
    }

    // MARK: - Sending again

    func testHeldRequestRunsOnceOnResume() {
        let queue = InterruptedRequestQueue()
        var runs = 0
        queue.hold { runs += 1 }
        XCTAssertTrue(queue.hasPending)
        queue.resume()
        queue.resume()
        XCTAssertEqual(runs, 1)
        XCTAssertFalse(queue.hasPending)
    }

    func testOnlyLatestRequestIsKept() {
        let queue = InterruptedRequestQueue()
        var sent: [String] = []
        queue.hold { sent.append("first") }
        queue.hold { sent.append("second") }
        queue.resume()
        XCTAssertEqual(sent, ["second"])
    }

    func testResumeWithNothingHeldDoesNothing() {
        InterruptedRequestQueue().resume()
    }
}
