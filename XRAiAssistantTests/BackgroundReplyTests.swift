import XCTest
@testable import XRAiAssistant

/// Guards replies that must arrive after the user leaves the app: the request
/// handed to the background session must match each provider's API, its reply
/// must be read correctly, and finished replies must survive a relaunch.
final class BackgroundReplyTests: XCTestCase {

    private func inputs(provider: String, model: String = "m", control: AIModelControl = .sampling) -> BackgroundReplyRequests.Inputs {
        .init(provider: provider, model: model, systemPrompt: "SYS", userMessage: "make a cube",
              apiKey: "KEY", temperature: 0.7, topP: 0.9, effort: .high, control: control, maxOutputTokens: 1000)
    }

    private func body(_ request: URLRequest?) -> [String: Any] {
        guard let data = request?.httpBody else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // MARK: Requests

    func testOpenAICompatibleRequestsAreNonStreaming() {
        for (provider, host) in [("OpenAI", "api.openai.com"), ("xAI", "api.x.ai"), ("Together.ai", "api.together.xyz")] {
            let request = BackgroundReplyRequests.request(for: inputs(provider: provider))
            XCTAssertEqual(request?.url?.host, host, provider)
            XCTAssertEqual(request?.url?.path, "/v1/chat/completions", provider)
            XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer KEY", provider)
            let json = body(request)
            XCTAssertEqual(json["stream"] as? Bool, false, provider)
            let messages = json["messages"] as? [[String: String]]
            XCTAssertEqual(messages?.first?["content"], "SYS", provider)
            XCTAssertEqual(messages?.last?["content"], "make a cube", provider)
        }
    }

    func testOpenAIEffortModelsUseEffortFields() {
        let json = body(BackgroundReplyRequests.request(for: inputs(provider: "OpenAI", control: .effort)))
        XCTAssertEqual(json["reasoning_effort"] as? String, "high")
        XCTAssertEqual(json["max_completion_tokens"] as? Int, 1000)
        XCTAssertNil(json["temperature"], "effort models reject temperature")
    }

    func testAnthropicRequest() {
        let request = BackgroundReplyRequests.request(for: inputs(provider: "Anthropic", control: .effort))
        XCTAssertEqual(request?.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-api-key"), "KEY")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let json = body(request)
        XCTAssertEqual(json["system"] as? String, "SYS")
        XCTAssertNil(json["stream"])
        XCTAssertNil(json["temperature"], "Claude 5 rejects temperature")
        XCTAssertEqual((json["output_config"] as? [String: String])?["effort"], "high")
    }

    func testGoogleRequest() {
        let request = BackgroundReplyRequests.request(for: inputs(provider: "Google AI", model: "gemini-2.5-pro"))
        XCTAssertEqual(request?.url?.path, "/v1beta/models/gemini-2.5-pro:generateContent")
        XCTAssertTrue(request?.url?.query?.contains("key=KEY") == true)
        XCTAssertNotNil(body(request)["systemInstruction"])
    }

    func testLocalServerRequest() {
        let savedURL = LocalServerConfig.baseURL, savedModel = LocalServerConfig.modelName
        defer { LocalServerConfig.baseURL = savedURL; LocalServerConfig.modelName = savedModel }
        LocalServerConfig.baseURL = "192.168.1.20:11434"
        LocalServerConfig.modelName = "qwen"
        var local = inputs(provider: "Local", model: "local:qwen")
        local = .init(provider: local.provider, model: local.model, systemPrompt: "SYS", userMessage: "hi",
                      apiKey: "changeMe", temperature: 0.7, topP: 0.9, effort: .high, control: .sampling, maxOutputTokens: 1000)
        let request = BackgroundReplyRequests.request(for: local)
        XCTAssertEqual(request?.url?.absoluteString, "http://192.168.1.20:11434/v1/chat/completions")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"), "no key means no auth header")
        XCTAssertEqual(body(request)["model"] as? String, "qwen")
    }

    func testUnknownProviderHasNoBackgroundPath() {
        XCTAssertNil(BackgroundReplyRequests.request(for: inputs(provider: "LlamaStack")))
    }

    // MARK: Reading replies

    func testRepliesAreReadPerProvider() {
        let openAI = #"{"choices":[{"message":{"role":"assistant","content":"cube ✅"}}]}"#
        XCTAssertEqual(BackgroundReplyRequests.replyText(provider: "OpenAI", data: Data(openAI.utf8)), "cube ✅")

        let anthropic = #"{"content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"A "},{"type":"text","text":"cube"}]}"#
        XCTAssertEqual(BackgroundReplyRequests.replyText(provider: "Anthropic", data: Data(anthropic.utf8)), "A cube",
                       "thinking blocks are not part of the reply")

        let google = #"{"candidates":[{"content":{"parts":[{"text":"plan","thought":true},{"text":"cube"}]}}]}"#
        XCTAssertEqual(BackgroundReplyRequests.replyText(provider: "Google AI", data: Data(google.utf8)), "cube",
                       "thought parts are not part of the reply")

        XCTAssertNil(BackgroundReplyRequests.replyText(provider: "OpenAI", data: Data("not json".utf8)))
        XCTAssertNil(BackgroundReplyRequests.replyText(provider: "OpenAI", data: Data(#"{"choices":[]}"#.utf8)))
    }

    // MARK: Saved results

    func testFinishedRepliesSurviveARelaunch() {
        let suite = "BackgroundReplyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        BackgroundReplyService(store: defaults).save(.init(jobID: "a", text: "reply", error: nil))
        // A new service, as after a relaunch, still sees it.
        let relaunched = BackgroundReplyService(store: defaults)
        XCTAssertEqual(relaunched.outcome(jobID: "a")?.text, "reply")
        XCTAssertEqual(relaunched.uncollectedOutcomes().count, 1)

        relaunched.removeOutcome(jobID: "a")
        XCTAssertNil(relaunched.outcome(jobID: "a"))
        XCTAssertTrue(relaunched.uncollectedOutcomes().isEmpty)
    }

    func testSavingTheSameJobReplacesIt() {
        let suite = "BackgroundReplyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = BackgroundReplyService(store: defaults)
        service.save(.init(jobID: "a", text: nil, error: "first"))
        service.save(.init(jobID: "a", text: "second", error: nil))
        XCTAssertEqual(service.uncollectedOutcomes(), [.init(jobID: "a", text: "second", error: nil)])
    }
}
