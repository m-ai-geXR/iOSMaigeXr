import XCTest
@testable import XRAiAssistant

/// Together retires models; the default and every migration target must be
/// ones it still serves, and retired ids must not be offered.
@MainActor
final class TogetherLineupTests: XCTestCase {

    private let offered = Set(TogetherAIProvider().models.map(\.id))
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
