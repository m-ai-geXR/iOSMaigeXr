import XCTest
@testable import XRAiAssistant

/// A model whose provider has no key asks for one up front (as on Android),
/// and a key error offers to add the key instead of a dead-end alert.
@MainActor
final class KeyPromptTests: XCTestCase {

    private var savedKey: String?
    override func setUp() async throws {
        savedKey = APIKeyStore.key(for: "OpenAI")
        APIKeyStore.deleteKey(for: "OpenAI")
    }
    override func tearDown() async throws {
        if let savedKey { APIKeyStore.setKey(savedKey, for: "OpenAI") }
    }

    private func openAIModel(_ vm: ChatViewModel) throws -> String {
        try XCTUnwrap(vm.modelsByProvider["OpenAI"]?.first?.id)
    }

    func testModelWithoutKeyIsReported() throws {
        let vm = ChatViewModel()
        vm.setAPIKey(for: "OpenAI", key: "changeMe")
        XCTAssertEqual(vm.providerMissingKey(for: try openAIModel(vm)), "OpenAI")
    }

    func testPickingThatModelAsksForTheKey() throws {
        let vm = ChatViewModel()
        vm.setAPIKey(for: "OpenAI", key: "changeMe")
        let model = try openAIModel(vm)
        vm.selectModel(model)
        XCTAssertEqual(vm.selectedModel, model)
        XCTAssertEqual(vm.keyPrompt?.provider, "OpenAI")
    }

    func testModelWithKeyDoesNotAsk() throws {
        let vm = ChatViewModel()
        vm.setAPIKey(for: "OpenAI", key: "sk-test-0123456789abcdefghijklmnop")
        let model = try openAIModel(vm)
        XCTAssertNil(vm.providerMissingKey(for: model))
        vm.selectModel(model)
        XCTAssertNil(vm.keyPrompt)
    }

    func testKeyErrorsOfferToAddTheKey() {
        let vm = ChatViewModel()
        vm.errorMessage = "⚠️ API Key Required: Please configure your OpenAI API key in Settings"
        XCTAssertTrue(vm.errorIsAboutKey)
        vm.promptForKeyAfterError()
        XCTAssertNil(vm.errorMessage)
        XCTAssertTrue(vm.retryAfterKey)
        XCTAssertNotNil(vm.keyPrompt)

        vm.errorMessage = "The reply did not arrive. Check your connection and try again."
        XCTAssertFalse(vm.errorIsAboutKey)
    }
}
