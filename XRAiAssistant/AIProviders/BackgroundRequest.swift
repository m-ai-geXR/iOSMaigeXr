import UIKit

/// Keeps an AI request alive when the user leaves the app, and says whether a
/// failure was the connection being cut rather than a real error.
///
/// iOS suspends an app a few seconds after it goes to the background, which
/// drops any open connection. A background task asks the system for time to
/// finish the request. If the connection is still cut, the caller holds the
/// request in `InterruptedRequestQueue` and sends it again when the app is back.

/// The part of UIApplication that grants background time, so tests can count
/// begin and end calls without a running app.
protocol BackgroundTaskHosting {
    func begin(name: String, onExpire: @escaping () -> Void) -> UIBackgroundTaskIdentifier
    func end(_ identifier: UIBackgroundTaskIdentifier)
}

struct ApplicationBackgroundHost: BackgroundTaskHosting {
    func begin(name: String, onExpire: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: name) { onExpire() }
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

@MainActor
enum BackgroundRequest {

    /// Runs `operation` inside a background task. The task always ends, whether
    /// the operation returns, throws, or the system runs out of time first.
    static func run<T>(
        _ name: String,
        host: BackgroundTaskHosting = ApplicationBackgroundHost(),
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let task = TaskHandle(host: host)
        task.id = host.begin(name: name) { task.finish() }
        defer { task.finish() }
        return try await operation()
    }

    /// True when the request failed because the connection went away (the app
    /// was suspended, or the network dropped), so sending it again can work.
    static func isInterruption(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return interruptionCodes.contains(urlError.code)
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return interruptionCodes.contains(URLError.Code(rawValue: nsError.code))
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isInterruption(underlying)
        }
        // Some provider clients wrap the URL error in their own type and keep
        // only its description.
        let text = error.localizedDescription.lowercased()
        return text.contains("network connection was lost")
            || text.contains("socket is not connected")
            || text.contains("software caused connection abort")
    }

    private static let interruptionCodes: Set<URLError.Code> = [
        .networkConnectionLost,
        .notConnectedToInternet,
        .timedOut,
        .cannotConnectToHost,
        .backgroundSessionWasDisconnected,
        .dataNotAllowed
    ]

    private final class TaskHandle {
        let host: BackgroundTaskHosting
        var id: UIBackgroundTaskIdentifier = .invalid

        init(host: BackgroundTaskHosting) { self.host = host }

        func finish() {
            guard id != .invalid else { return }
            host.end(id)
            id = .invalid
        }
    }
}

/// Holds one interrupted request and sends it again once the app is active.
/// Only the latest request is kept, and each is retried once.
@MainActor
final class InterruptedRequestQueue {
    private var pending: (() -> Void)?

    var hasPending: Bool { pending != nil }

    func hold(_ retry: @escaping () -> Void) {
        pending = retry
    }

    /// Sends the held request, if any. Call when the app becomes active.
    func resume() {
        guard let retry = pending else { return }
        pending = nil
        retry()
    }
}

/// What a reply shows: reasoning models such as DeepSeek R1 wrap their
/// thinking in <think>…</think>, which is not part of the answer.
enum ReplyText {
    /// The answer with any thinking removed, and whether the model is still
    /// inside an unfinished <think> block (shown as "Thinking…").
    static func visible(_ raw: String) -> (text: String, isThinking: Bool) {
        var text = raw
        var isThinking = false
        while let open = text.range(of: "<think>") {
            if let close = text.range(of: "</think>", range: open.upperBound..<text.endIndex) {
                text.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                text.removeSubrange(open.lowerBound..<text.endIndex)
                isThinking = true
            }
        }
        // Some servers omit the opening tag and send only the closing one.
        if let close = text.range(of: "</think>") {
            text.removeSubrange(text.startIndex..<close.upperBound)
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), isThinking)
    }
}
