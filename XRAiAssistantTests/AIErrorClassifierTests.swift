import XCTest
@testable import XRAiAssistant

/// The point of these is the guarantees, not the individual mappings: the user
/// always gets a cause and a next step, and never a response body.
final class AIErrorClassifierTests: XCTestCase {

    // MARK: - By status

    func testMapsHTTPStatusesToCategories() {
        let cases: [(Int, AIErrorCategory)] = [
            (401, .invalidAPIKey),
            (402, .quotaExceeded),
            (403, .accessDenied),
            (404, .modelUnavailable),
            (429, .rateLimited),
            (500, .serverError),
            (503, .serverError),
        ]
        for (status, expected) in cases {
            let info = AIErrorClassifier.classify(AIProviderHTTPError(provider: "Anthropic", status: status))
            XCTAssertEqual(info.category, expected, "status \(status)")
        }
    }

    func testNamesTheProviderSoTheUserKnowsWhichKeyToCheck() {
        let info = AIErrorClassifier.classify(AIProviderHTTPError(provider: "Together.ai", status: 401))
        XCTAssertTrue(info.message.contains("Together.ai"))
    }

    func testTransientFailuresAreRetryableAndPermanentOnesAreNot() {
        XCTAssertTrue(AIErrorClassifier.classify(AIProviderHTTPError(provider: "x", status: 429)).retryable)
        XCTAssertTrue(AIErrorClassifier.classify(AIProviderHTTPError(provider: "x", status: 503)).retryable)
        XCTAssertFalse(AIErrorClassifier.classify(AIProviderHTTPError(provider: "x", status: 401)).retryable)
        XCTAssertFalse(AIErrorClassifier.classify(AIProviderHTTPError(provider: "x", status: 402)).retryable)
    }

    // MARK: - URLError, which is how connectivity actually arrives

    func testDetectsOfflineFromURLError() {
        for code in [URLError.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed] {
            let info = AIErrorClassifier.classify(URLError(code))
            XCTAssertEqual(info.category, .offline, "\(code)")
        }
    }

    func testDetectsTimeoutFromURLError() {
        XCTAssertEqual(AIErrorClassifier.classify(URLError(.timedOut)).category, .timeout)
    }

    // MARK: - The existing typed errors still map

    func testExistingProviderErrorsMapToTheSameCategories() {
        XCTAssertEqual(AIErrorClassifier.classify(AIProviderError.invalidAPIKey).category, .invalidAPIKey)
        XCTAssertEqual(AIErrorClassifier.classify(AIProviderError.rateLimitExceeded).category, .rateLimited)
        XCTAssertEqual(AIErrorClassifier.classify(AIProviderError.modelNotSupported).category, .modelUnavailable)
        XCTAssertEqual(AIErrorClassifier.classify(AIProviderError.responseEmpty).category, .emptyResponse)
    }

    func testDetectsMissingKeyHoweverItIsSpelled() {
        for text in ["API key not configured", "apiKey is required", "api_key still set to changeMe"] {
            let info = AIErrorClassifier.classify(AIProviderError.configurationError(text))
            XCTAssertEqual(info.category, .missingAPIKey, text)
        }
    }

    func testDetectsContextOverflow() {
        let info = AIErrorClassifier.classify(AIProviderError.networkError("maximum context length is 8192 tokens"))
        XCTAssertEqual(info.category, .contextTooLong)
    }

    // MARK: - The guarantees

    func testNeverLeaksAProviderResponseBody() {
        let body = #"{"error":{"message":"invalid x-api-key","type":"authentication_error"}}"#
        let info = AIErrorClassifier.classify(
            AIProviderHTTPError(provider: "Anthropic", status: 401, providerMessage: body))

        XCTAssertFalse(info.message.contains("x-api-key"))
        XCTAssertFalse(info.message.contains("{"))
        XCTAssertFalse(info.asMessage.contains(body))
    }

    func testDoesNotShowABareStatusCode() {
        let info = AIErrorClassifier.classify(AIProviderHTTPError(provider: "OpenAI", status: 401))
        XCTAssertFalse(info.message.contains("401"))
    }

    func testAlwaysGivesTheUserSomethingToDo() {
        let errors: [Error?] = [
            AIProviderHTTPError(provider: "x", status: 401),
            AIProviderHTTPError(provider: "x", status: 429),
            AIProviderHTTPError(provider: "x", status: 500),
            URLError(.notConnectedToInternet),
            AIProviderError.responseEmpty,
            NSError(domain: "nobody.anticipated", code: -1),
            nil,
        ]
        for error in errors {
            let info = AIErrorClassifier.classify(error)
            XCTAssertFalse(info.title.isEmpty)
            XCTAssertFalse(info.message.isEmpty)
            XCTAssertFalse(info.action.isEmpty)
        }
    }

    func testNilErrorDoesNotCrash() {
        XCTAssertEqual(AIErrorClassifier.classify(nil).category, .unknown)
    }

    func testUnrecognisedFailuresStillProduceAUsableMessage() {
        let info = AIErrorClassifier.classify(NSError(domain: "weird", code: 7))
        XCTAssertEqual(info.category, .unknown)
        XCTAssertTrue(info.action.contains("Settings"))
    }

    // MARK: - Formatting

    func testLineFormIsSingleLineAndMessageFormCarriesAllThreeParts() {
        let info = AIErrorClassifier.classify(AIProviderHTTPError(provider: "OpenAI", status: 429))
        XCTAssertFalse(info.asLine.contains("\n"))

        let body = info.asMessage
        XCTAssertTrue(body.contains(info.title))
        XCTAssertTrue(body.contains(info.message))
        XCTAssertTrue(body.contains(info.action))
    }
}
