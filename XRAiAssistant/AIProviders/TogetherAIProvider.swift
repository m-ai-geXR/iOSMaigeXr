import Foundation

class TogetherAIProvider: AIProvider {
    let name = "Together.ai"
    let requiresAPIKey = true

    private var apiKey: String?

    let capabilities = AIProviderCapabilities(
        supportsVision: false,
        supportsStreaming: true,
        supportedImageFormats: [],
        maxImageSize: 0,
        maxImagesPerMessage: 0,
        maxTokens: 32_768  // Typical context window
    )

    let models: [AIModel] = [
        // Latest open models on Together (checked 2026-10-07). 1M-token context.
        AIModel(
            id: "moonshotai/Kimi-K3",
            displayName: "Kimi K3",
            description: "Moonshot flagship - strong agentic coding",
            pricing: "$3.00/1M input tokens",
            provider: "Together.ai",
            maxOutputTokens: 32_000
        ),
        AIModel(
            id: "zai-org/GLM-5.3",
            displayName: "GLM-5.3",
            description: "Z.ai flagship - advanced coding and reasoning",
            pricing: "$1.40/1M input tokens",
            provider: "Together.ai",
            control: .effort,
            maxOutputTokens: 32_000
        ),
        AIModel(
            id: "zai-org/GLM-5.3-Flash",
            displayName: "GLM-5.3 Flash",
            description: "Fast, low-cost GLM for quick scenes",
            pricing: "$0.15/1M input tokens",
            provider: "Together.ai",
            isDefault: true,
            control: .effort,
            maxOutputTokens: 32_000
        ),
        AIModel(
            id: "deepseek-ai/DeepSeek-V4.1-Flash",
            displayName: "DeepSeek V4.1 Flash",
            description: "Fast DeepSeek for coding",
            pricing: "Serverless",
            provider: "Together.ai",
            maxOutputTokens: 16_000
        ),
        AIModel(
            id: "deepseek-ai/DeepSeek-V4-Pro-0813",
            displayName: "DeepSeek V4 Pro",
            description: "DeepSeek flagship - deep reasoning",
            pricing: "Serverless",
            provider: "Together.ai",
            maxOutputTokens: 16_000
        ),
        AIModel(
            id: "Qwen/Qwen3.8-Flash",
            displayName: "Qwen3.8 Flash",
            description: "Fast Qwen for quick edits",
            pricing: "Serverless",
            provider: "Together.ai",
            maxOutputTokens: 16_000
        ),
        AIModel(
            id: "Qwen/Qwen3.7-Max",
            displayName: "Qwen3.7 Max",
            description: "Qwen flagship - strong coding",
            pricing: "Serverless",
            provider: "Together.ai",
            maxOutputTokens: 16_000
        ),
        AIModel(
            id: "meta-llama/Llama-3.3-70B-Instruct-Turbo",
            displayName: "Llama 3.3 70B Turbo",
            description: "Meta large model",
            pricing: "Serverless",
            provider: "Together.ai",
            maxOutputTokens: 8_000
        )
    ]
    
    func configure(apiKey: String) {
        self.apiKey = apiKey
        print("🔧 Together.ai provider configured")
    }

    func generateResponse(
        messages: [AIMessage],
        model: String,
        temperature: Double,
        topP: Double,
        effort: AIEffort
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let apiKey, !apiKey.isEmpty,
              let url = URL(string: "https://api.together.xyz/v1/chat/completions") else {
            throw AIProviderError.configurationError("Provider not configured with API key")
        }

        // Each model's own output budget; reasoning models need room to think and answer.
        let maxTokens = models.first(where: { $0.id == model })?.maxOutputTokens ?? 8_000
        let temperature = SamplingLimits.temperature(temperature, model: model)
        let topP = SamplingLimits.topP(topP, model: model)

        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { message -> [String: String] in
                let role: String
                switch message.role {
                case .system: role = "system"
                case .user: role = "user"
                case .assistant: role = "assistant"
                }
                return ["role": role, "content": message.textContent]
            },
            "max_tokens": maxTokens,
            "temperature": temperature,
            "top_p": topP,
            "stream": true
        ]
        if let reasoningEffort = TogetherReasoning.effort(for: model, appEffort: effort) {
            body["reasoning_effort"] = reasoningEffort
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300 // reasoning models can think for minutes
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("🚀 Together.ai request: model=\(model), temp=\(temperature), top-p=\(topP), max-tokens=\(maxTokens)")

        let providerName = name
        return AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var errorBody = ""
                        for try await line in bytes.lines { errorBody += line }
                        throw AIProviderHTTPError(provider: providerName, status: http.statusCode, providerMessage: errorBody)
                    }
                    var parser = StreamParser()
                    for try await line in bytes.lines {
                        if line.trimmingCharacters(in: .whitespaces) == "data: [DONE]" { break }
                        if let text = parser.text(fromLine: line) { continuation.yield(text) }
                    }
                    if let closing = parser.finish() { continuation.yield(closing) }
                    continuation.finish()
                } catch {
                    print("❌ Together.ai error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reads Together's stream. Reasoning models (GLM, Kimi, DeepSeek) send
    /// their thinking in `delta.reasoning` with no `content` for a long time;
    /// it is passed on inside <think> tags so the app shows "Thinking…" and
    /// knows the reply is alive, and ReplyText hides it from the answer.
    struct StreamParser {
        private var inThinking = false

        mutating func text(fromLine line: String) -> String? {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { return nil }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let delta = (json["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any]
            else { return nil }
            var out = ""
            if let reasoning = (delta["reasoning"] ?? delta["reasoning_content"]) as? String, !reasoning.isEmpty {
                if !inThinking { out += "<think>"; inThinking = true }
                out += reasoning
            }
            if let content = delta["content"] as? String, !content.isEmpty {
                if inThinking { out += "</think>"; inThinking = false }
                out += content
            }
            return out.isEmpty ? nil : out
        }

        mutating func finish() -> String? {
            guard inThinking else { return nil }
            inThinking = false
            return "</think>"
        }
    }
}
