import XCTest
@testable import XRAiAssistant

/// GLM and Kimi on Together reject top_p below 0.95 with a 400, and the app's
/// default is 0.9. Requests must stay inside each model's range, and if a
/// provider still refuses a setting the user sees a readable message, not the
/// raw response body.
final class SamplingLimitsTests: XCTestCase {

    func testDefaultsAreRaisedForGLMAndKimi() {
        for model in ["zai-org/GLM-5.3", "zai-org/GLM-5.3-Flash", "moonshotai/Kimi-K3"] {
            XCTAssertEqual(SamplingLimits.topP(0.9, model: model), 0.95, model)
            XCTAssertEqual(SamplingLimits.topP(1.0, model: model), 1.0, model)
            XCTAssertEqual(SamplingLimits.temperature(1.5, model: model), 1.0, model)
        }
    }

    func testOtherModelsKeepTheUsersValues() {
        XCTAssertEqual(SamplingLimits.topP(0.9, model: "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo"), 0.9)
        XCTAssertEqual(SamplingLimits.temperature(1.5, model: "Qwen/Qwen2.5-7B-Instruct-Turbo"), 1.5)
    }

    func testBackgroundRequestsUseTheModelsRange() throws {
        let inputs = BackgroundReplyRequests.Inputs(
            provider: "Together.ai", model: "zai-org/GLM-5.3-Flash", systemPrompt: "SYS", userMessage: "cube",
            apiKey: "KEY", temperature: 0.7, topP: 0.9, effort: .high, control: .sampling, maxOutputTokens: 1000)
        let data = try XCTUnwrap(BackgroundReplyRequests.request(for: inputs)?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["top_p"] as? Double, 0.95)
    }

    func testOutOfRangeErrorsReadCleanly() {
        let raw = #"{"error":{"message":"top_p must be between 0.95 and 1","type":"invalid_request_error"}}"#
        let info = AIErrorClassifier.classify(AIProviderHTTPError(provider: "Together.ai", status: nil, providerMessage: raw))
        XCTAssertEqual(info.category, .invalidRequest)
        XCTAssertFalse(info.asMessage.contains("{"), "no raw JSON in the message")

        let bare400 = AIErrorClassifier.classify(AIProviderHTTPError(provider: "Together.ai", status: 400))
        XCTAssertEqual(bare400.category, .invalidRequest)
    }
}
