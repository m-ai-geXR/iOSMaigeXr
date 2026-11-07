import AppTrackingTransparency
import UIKit

/// An interrupted system request is not a refusal. Keep ads blocked until the
/// system has a decision, and give a transient presentation conflict one retry.
@MainActor
struct TrackingAuthorizationResolver {
    var status: () -> ATTrackingManager.AuthorizationStatus = {
        ATTrackingManager.trackingAuthorizationStatus
    }
    var request: () async -> ATTrackingManager.AuthorizationStatus = {
        await ATTrackingManager.requestTrackingAuthorization()
    }
    var waitUntilReady: () async throws -> Void = {
        try await TrackingAuthorizationResolver.waitForPresentation()
    }

    func resolve() async throws -> ATTrackingManager.AuthorizationStatus {
        for _ in 0..<2 {
            try Task.checkCancellation()
            let current = status()
            guard current == .notDetermined else { return current }
            try await waitUntilReady()
            try Task.checkCancellation()
            // UMP may have obtained the decision while presenting its own form.
            let latest = status()
            guard latest == .notDetermined else { return latest }
            let result = await request()
            if result != .notDetermined { return result }
        }
        return status()
    }

    /// ATT only presents while active. Allow foreground and sheet transitions
    /// to settle, then recheck; a fixed delay alone cannot establish readiness.
    static func waitForPresentation() async throws {
        while true {
            try Task.checkCancellation()
            if presentationIsReady {
                try await Task.sleep(for: .milliseconds(500))
                if presentationIsReady { return }
            } else {
                try await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private static var presentationIsReady: Bool {
        guard UIApplication.shared.applicationState == .active,
              let presenter = UIApplication.shared.topMostViewController,
              presenter.viewIfLoaded?.window != nil else { return false }
        return !presenter.isBeingPresented && !presenter.isBeingDismissed
            && presenter.transitionCoordinator == nil
            && !(presenter is UIAlertController)
    }
}
