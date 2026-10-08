import XCTest
@testable import XRAiAssistant

/// Together retires models; the default and every migration target must be
/// ones it still serves, and retired ids must not be offered.
@MainActor
final class TogetherLineupTests: XCTestCase {

    private let offered = Set(TogetherAIProvider.curatedModels.map(\.id))
    private let retired = ["deepseek-ai/DeepSeek-R1", "meta-llama/Meta-Llama-3-8B-Instruct-Lite",
                           "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo", "Qwen/Qwen2.5-7B-Instruct-Turbo",
                           "deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free"]

    func testDefaultIsOffered() {
        XCTAssertTrue(offered.contains("zai-org/GLM-5.3-Flash"))
    }

    func testRetiredModelsAreGoneAndMigrated() {
        for id in retired {
            XCTAssertFalse(offered.contains(id), id)
            let target = ChatViewModel.modelMigrations[id]
            XCTAssertNotNil(target, id)
            XCTAssertTrue(offered.contains(target ?? ""), "\(id) -> \(target ?? "nil")")
        }
        XCTAssertTrue(ChatViewModel().availableModels.isEmpty, "no legacy list of retired models")
    }
}

/// GLM thinks for minutes at its default depth; requests must carry a lighter effort.
final class GLMReasoningEffortTests: XCTestCase {

    func testGLMGetsALighterEffort() {
        XCTAssertEqual(TogetherReasoning.effort(for: "zai-org/GLM-5.3", appEffort: .high), "medium")
        XCTAssertEqual(TogetherReasoning.effort(for: "zai-org/GLM-5.3-Flash", appEffort: .medium), "low")
        XCTAssertEqual(TogetherReasoning.effort(for: "zai-org/GLM-5.3", appEffort: .max), "max")
        XCTAssertNil(TogetherReasoning.effort(for: "moonshotai/Kimi-K3", appEffort: .high))
    }

    func testBackgroundRequestCarriesTheEffort() throws {
        let inputs = BackgroundReplyRequests.Inputs(
            provider: "Together.ai", model: "zai-org/GLM-5.3", systemPrompt: "S", userMessage: "U",
            apiKey: "K", temperature: 0.7, topP: 0.9, effort: .high, control: .effort, maxOutputTokens: 32_000)
        let data = try XCTUnwrap(BackgroundReplyRequests.request(for: inputs)?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["reasoning_effort"] as? String, "medium")
    }
}
