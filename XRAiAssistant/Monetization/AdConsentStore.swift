//
//  AdConsentStore.swift
//  m{ai}geXR
//
//  Resolves what the user has agreed to, once, above the provider.
//
//  Two separate things, often confused:
//
//  - **UMP** (Google's consent platform) covers the regional requirement —
//    EEA/UK and regulated US states. It decides whether ads may be requested
//    at all.
//  - **ATT** (Apple's tracking prompt) authorizes cross-company tracking and
//    access to the IDFA. Without it, requests use nonpersonalized ads.
//
//  Neither substitutes for the other, and declining either is a normal outcome
//  rather than an error. See docs/release/MONETIZATION.md step 3.
//

import SwiftUI
import AppTrackingTransparency
import UserMessagingPlatform
import OSLog

@MainActor
final class AdConsentStore: ObservableObject {

    static let shared = AdConsentStore()

    /// The resolved decision. `.unknown` until `resolve()` has run, which is
    /// what keeps providers from loading anything at launch.
    @Published private(set) var consent: AdConsent = .unknown

    /// True when the user must be given a standing way to change their mind.
    ///
    /// When UMP reports this, a one-time prompt is not enough — Settings has to
    /// carry a permanent control. This is the part most commonly missed.
    @Published private(set) var privacyOptionsRequired = false

    private init() {}

    private var resolutionTask: Task<AdConsent, Never>?
    private let logger = Logger(subsystem: "studio.seacloud9.maigexr", category: "AdConsent")

    // MARK: - Resolving

    /// Gather consent and return the result.
    ///
    /// Call after the first UI is on screen: both the UMP form and the ATT
    /// prompt are system sheets, and presenting them over a splash screen means
    /// presenting them over nothing.
    @discardableResult
    func resolve() async -> AdConsent {
        if let resolutionTask { return await resolutionTask.value }
        let task = Task { await self.resolveOnce() }
        resolutionTask = task
        let result = await task.value
        resolutionTask = nil
        return result
    }

    private func resolveOnce() async -> AdConsent {
        log("waiting for an active presentation before consent")
        do {
            try await TrackingAuthorizationResolver.waitForPresentation()
        } catch {
            consent = .unknown
            return consent
        }
        log("updating UMP consent information")
        if let error = await requestConsentInfoUpdate() {
            // Without an answer we must not assume permission. No ads this
            // session; the next launch tries again.
            log("consent info update failed: \(error.localizedDescription)")
            consent = .unknown
            return consent
        }

        await presentFormIfRequired()

        privacyOptionsRequired =
            ConsentInformation.shared.privacyOptionsRequirementStatus == .required

        guard ConsentInformation.shared.canRequestAds else {
            log("UMP says ads may not be requested")
            consent = .denied
            return consent
        }

        do {
            log("UMP permits ads; resolving ATT before ad initialization")
            let status = try await TrackingAuthorizationResolver().resolve()
            log("ATT status: \(status.rawValue)")
            switch status {
            case .authorized: consent = .personalised
            case .denied, .restricted: consent = .nonPersonalised
            case .notDetermined: consent = .unknown
            @unknown default: consent = .unknown
            }
        } catch {
            consent = .unknown
        }
        log("resolved \(consent)")
        return consent
    }

    /// Re-read consent after the user changes it in the privacy options form.
    func refreshAfterPrivacyOptionsChange() async {
        guard ConsentInformation.shared.canRequestAds else {
            consent = .denied
            return
        }
        // If the original prompt was interrupted, privacy options must not
        // turn that unanswered request into permission to initialize ads.
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .authorized: consent = .personalised
        case .denied, .restricted: consent = .nonPersonalised
        case .notDetermined: consent = .unknown
        @unknown default: consent = .unknown
        }
    }

    // MARK: - Privacy options

    /// Present the form that lets a user change a decision they already made.
    /// Only meaningful while `privacyOptionsRequired` is true.
    func presentPrivacyOptions() async {
        await withCheckedContinuation { continuation in
            ConsentForm.presentPrivacyOptionsForm(
                from: UIApplication.shared.topMostViewController
            ) { error in
                if let error { self.log("privacy options: \(error.localizedDescription)") }
                continuation.resume()
            }
        }

        await refreshAfterPrivacyOptionsChange()
        await AdManager.shared.updateConsent(consent)
    }

    // MARK: - UMP

    private func requestConsentInfoUpdate() async -> Error? {
        let parameters = RequestParameters()
        parameters.debugSettings = Self.debugSettings()

        return await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                continuation.resume(returning: error)
            }
        }
    }

    private func presentFormIfRequired() async {
        await withCheckedContinuation { continuation in
            // Calls back on the next run loop even when no form is shown, so
            // this cannot hang waiting for a form that was never required.
            ConsentForm.loadAndPresentIfRequired(
                from: UIApplication.shared.topMostViewController
            ) { error in
                if let error { self.log("form: \(error.localizedDescription)") }
                continuation.resume()
            }
        }
    }

    /// Lets a debug build see the EEA form without travelling.
    ///
    /// `UMP_DEBUG_GEOGRAPHY=eea` plus `UMP_TEST_DEVICE_ID=<id>`, where the id is
    /// printed by the UMP SDK on first run. Returns nil in release, so no debug
    /// geography can ever ship.
    private static func debugSettings() -> DebugSettings? {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard let geography = environment["UMP_DEBUG_GEOGRAPHY"]?.lowercased() else { return nil }

        let settings = DebugSettings()
        switch geography {
        case "eea": settings.geography = .EEA
        case "us": settings.geography = .regulatedUSState
        case "other": settings.geography = .other
        default: return nil
        }
        if let id = environment["UMP_TEST_DEVICE_ID"] {
            settings.testDeviceIdentifiers = [id]
        }
        return settings
        #else
        return nil
        #endif
    }

    // MARK: - Internals

    /// `nonisolated` because the UMP completion handlers are nonisolated
    /// closures. Hopping to the main actor just to log would reorder the lines
    /// relative to the work they describe.
    private nonisolated func log(_ message: String) {
        // No prompts, keys or identifiers: release-device diagnostics need only
        // the gate reached and system authorization status.
        logger.notice("\(message, privacy: .public)")
        if AppConfig.showAdDebugLogs { print("🎯 Consent: \(message)") }
    }
}
