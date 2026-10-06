//
//  AIErrorClassifier.swift
//  m{ai}geXR
//
//  Turning provider failures into messages a person can act on.
//
//  AIProviderError already described failures, but its text stopped at what
//  happened — "Invalid API key provided" — without saying where to fix it, and
//  anything unrecognised fell through to a raw localizedDescription.
//
//  The taxonomy matches the web and Android clients so all three say the same
//  thing about the same failure.
//

import Foundation

enum AIErrorCategory {
    case missingAPIKey
    case invalidAPIKey
    case accessDenied
    case rateLimited
    case quotaExceeded
    case modelUnavailable
    case contextTooLong
    case serverError
    case timeout
    case offline
    case emptyResponse
    case unknown
}

struct AIErrorInfo {
    /// Short, for the heading.
    let title: String
    /// What happened, with no status codes or response bodies.
    let message: String
    /// The next thing to try. Never empty: a dead end is not a useful error.
    let action: String
    let category: AIErrorCategory
    /// Whether repeating the same request could plausibly work.
    let retryable: Bool

    /// One line, for a banner.
    var asLine: String { "\(title). \(action)" }

    /// Chat bubble: what happened, then what to do.
    var asMessage: String { "\(title)\n\n\(message)\n\n\(action)" }
}

/// Carries the HTTP status so classification reads a number, not prose.
struct AIProviderHTTPError: Error {
    let provider: String
    let status: Int?
    /// The provider's own body. Kept for logs, never shown raw.
    let providerMessage: String?

    init(provider: String, status: Int? = nil, providerMessage: String? = nil) {
        self.provider = provider
        self.status = status
        self.providerMessage = providerMessage
    }
}

enum AIErrorClassifier {

    private static let settingsHint = "Open Settings to check your API key."
    private static let defaultProvider = "The AI provider"

    static func classify(_ error: Error?, provider providerName: String = defaultProvider) -> AIErrorInfo {
        guard let error else { return unknown(providerName, status: nil) }

        if let http = error as? AIProviderHTTPError {
            let provider = http.provider.isEmpty ? providerName : http.provider
            if let status = http.status, let info = byStatus(status, provider) { return info }
            if let body = http.providerMessage, let info = byMessage(body, provider) { return info }
            return unknown(provider, status: http.status)
        }

        // URLSession reports connectivity through URLError, not prose.
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return timeout(providerName)
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed:
                return offline(providerName)
            default:
                break
            }
        }

        if let providerError = error as? AIProviderError {
            switch providerError {
            case .invalidAPIKey: return byStatus(401, providerName) ?? unknown(providerName, status: nil)
            case .rateLimitExceeded: return byStatus(429, providerName) ?? unknown(providerName, status: nil)
            case .modelNotSupported: return byStatus(404, providerName) ?? unknown(providerName, status: nil)
            case .responseEmpty: return emptyResponse(providerName)
            case .networkError(let text):
                return byMessage(text, providerName) ?? offline(providerName)
            case .configurationError(let text):
                return byMessage(text, providerName) ?? missingKey(providerName)
            default:
                break
            }
        }

        let text = (error as NSError).localizedDescription
        if !text.isEmpty {
            if let info = byMessage(text, providerName) { return info }
            if let match = text.range(of: #"\b[45]\d{2}\b"#, options: .regularExpression),
               let status = Int(text[match]),
               let info = byStatus(status, providerName) {
                return info
            }
        }
        return unknown(providerName, status: nil)
    }

    // MARK: - By status

    private static func byStatus(_ status: Int, _ provider: String) -> AIErrorInfo? {
        switch status {
        case 401:
            return AIErrorInfo(
                title: "API key rejected",
                message: "\(provider) did not accept your API key. It may be mistyped, revoked, or from a different provider.",
                action: "\(settingsHint) Keys often pick up a stray space when copied.",
                category: .invalidAPIKey, retryable: false)
        case 403:
            return AIErrorInfo(
                title: "Access denied",
                message: "Your \(provider) key is valid but is not allowed to use this model.",
                action: "Pick a different model, or enable access for this one in your provider dashboard.",
                category: .accessDenied, retryable: false)
        case 402:
            return AIErrorInfo(
                title: "Out of credit",
                message: "Your \(provider) account has no remaining balance for this request.",
                action: "Add credit in your provider dashboard, or switch to a free model.",
                category: .quotaExceeded, retryable: false)
        case 404:
            return AIErrorInfo(
                title: "Model unavailable",
                message: "\(provider) does not currently offer the selected model.",
                action: "Choose another model in Settings.",
                category: .modelUnavailable, retryable: false)
        case 429:
            return AIErrorInfo(
                title: "Too many requests",
                message: "\(provider) is rate limiting you, usually from sending several requests in quick succession.",
                action: "Wait a few seconds and try again. Free tiers have tighter limits.",
                category: .rateLimited, retryable: true)
        case 500...599:
            return AIErrorInfo(
                title: "\(provider) is having trouble",
                message: "The provider returned a server error. This is on their side, not yours.",
                action: "Try again shortly, or switch provider in Settings.",
                category: .serverError, retryable: true)
        default:
            return nil
        }
    }

    // MARK: - By message

    private static func byMessage(_ text: String, _ provider: String) -> AIErrorInfo? {
        let t = text.lowercased()

        // "api key", "apikey" and "api_key" all appear across the clients.
        let mentionsKey = t.contains("api key") || t.contains("apikey") || t.contains("api_key")
        if mentionsKey && (t.contains("not configured") || t.contains("required") || t.contains("changeme")) {
            return missingKey(provider)
        }
        if t.contains("context length") || t.contains("too many tokens") || t.contains("maximum context") {
            return AIErrorInfo(
                title: "Conversation too long",
                message: "This conversation has outgrown what the model can read at once.",
                action: "Start a new conversation, or switch to a model with a larger context window.",
                category: .contextTooLong, retryable: false)
        }
        if t.contains("timed out") || t.contains("timeout") {
            return timeout(provider)
        }
        if t.contains("offline") || t.contains("not connected") || t.contains("cannot reach")
            || t.contains("could not connect") || t.contains("hostname could not be found")
            || t.contains("network connection was lost") {
            return offline(provider)
        }
        if t.contains("empty response") || t.contains("no response body") {
            return emptyResponse(provider)
        }
        return nil
    }

    // MARK: - Shared cases

    private static func missingKey(_ provider: String) -> AIErrorInfo {
        AIErrorInfo(
            title: "API key needed",
            message: "\(provider) needs an API key before it can answer.",
            action: settingsHint,
            category: .missingAPIKey, retryable: false)
    }

    private static func timeout(_ provider: String) -> AIErrorInfo {
        AIErrorInfo(
            title: "Request timed out",
            message: "The model took too long to respond. Reasoning models can think for over a minute on hard scenes.",
            action: "Try again, or lower the reasoning effort in Settings for a faster answer.",
            category: .timeout, retryable: true)
    }

    private static func offline(_ provider: String) -> AIErrorInfo {
        AIErrorInfo(
            title: "No connection",
            message: "Could not reach \(provider).",
            action: "Check your internet connection and try again.",
            category: .offline, retryable: true)
    }

    private static func emptyResponse(_ provider: String) -> AIErrorInfo {
        AIErrorInfo(
            title: "Empty response",
            message: "\(provider) accepted the request but returned nothing.",
            action: "Try again. If it keeps happening, switch model or provider.",
            category: .emptyResponse, retryable: true)
    }

    private static func unknown(_ provider: String, status: Int?) -> AIErrorInfo {
        AIErrorInfo(
            title: "Something went wrong",
            message: status != nil
                ? "\(provider) returned an unexpected error (status \(status!))."
                : "\(provider) returned an unexpected error.",
            action: "Try again. If it keeps happening, switch model or provider in Settings.",
            category: .unknown, retryable: true)
    }
}
