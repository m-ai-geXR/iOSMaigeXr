import XCTest
@testable import XRAiAssistant

/// The Local model server: the address the user types must become the right
/// endpoint, and streamed replies must be read correctly.
final class LocalLLMProviderTests: XCTestCase {

    func testAddressFormsBecomeChatCompletionsURL() {
        let expected = "http://192.168.1.20:11434/v1/chat/completions"
        for input in ["192.168.1.20:11434", "http://192.168.1.20:11434", "http://192.168.1.20:11434/",
                      "http://192.168.1.20:11434/v1", "http://192.168.1.20:11434/v1/chat/completions",
                      "  http://192.168.1.20:11434/v1/  "] {
            XCTAssertEqual(LocalServerConfig.chatCompletionsURL(from: input)?.absoluteString, expected, input)
        }
    }

    func testHTTPSAndHostnamesAreKept() {
        XCTAssertEqual(LocalServerConfig.chatCompletionsURL(from: "https://llm.example.com")?.absoluteString,
                       "https://llm.example.com/v1/chat/completions")
        XCTAssertEqual(LocalServerConfig.chatCompletionsURL(from: "mac-studio.local:1234")?.absoluteString,
                       "http://mac-studio.local:1234/v1/chat/completions")
    }

    func testBadAddressesAreRejected() {
        XCTAssertNil(LocalServerConfig.chatCompletionsURL(from: ""))
        XCTAssertNil(LocalServerConfig.chatCompletionsURL(from: "   "))
        XCTAssertNil(LocalServerConfig.chatCompletionsURL(from: "ftp://server:21"))
        XCTAssertNil(LocalServerConfig.chatCompletionsURL(from: "file:///etc/passwd"))
    }

    func testModelPrefixIsStripped() {
        XCTAssertEqual(LocalServerConfig.serverModelName(from: "local:qwen2.5-coder:7b"), "qwen2.5-coder:7b")
        XCTAssertEqual(LocalServerConfig.serverModelName(from: "llama3"), "llama3")
    }

    func testStreamLinesAreParsed() {
        let line = #"data: {"choices":[{"delta":{"content":"héllo 🌀"}}]}"#
        XCTAssertEqual(LocalLLMProvider.content(fromStreamLine: line), "héllo 🌀")
        XCTAssertEqual(LocalLLMProvider.content(fromStreamLine: #"data:{"choices":[{"delta":{"content":"x"}}]}"#), "x")
        XCTAssertNil(LocalLLMProvider.content(fromStreamLine: "data: [DONE]"))
        XCTAssertNil(LocalLLMProvider.content(fromStreamLine: ": keep-alive"))
        XCTAssertNil(LocalLLMProvider.content(fromStreamLine: #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#))
    }

    func testProviderListsModelOnlyWhenConfigured() {
        let savedURL = LocalServerConfig.baseURL, savedModel = LocalServerConfig.modelName
        defer { LocalServerConfig.baseURL = savedURL; LocalServerConfig.modelName = savedModel }

        LocalServerConfig.baseURL = ""
        LocalServerConfig.modelName = ""
        XCTAssertTrue(LocalLLMProvider().models.isEmpty)

        LocalServerConfig.baseURL = "http://127.0.0.1:11434"
        LocalServerConfig.modelName = "llama3.2"
        let models = LocalLLMProvider().models
        XCTAssertEqual(models.map(\.id), ["local:llama3.2"])
        XCTAssertFalse(LocalLLMProvider().requiresAPIKey)
    }
}
