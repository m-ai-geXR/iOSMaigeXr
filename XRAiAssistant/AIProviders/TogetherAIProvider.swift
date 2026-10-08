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
            maxOutputTokens: 32_000
        ),
        AIModel(
            id: "zai-org/GLM-5.3-Flash",
            displayName: "GLM-5.3 Flash",
            description: "Fast, low-cost GLM for quick scenes",
            pricing: "$0.15/1M input tokens",
            provider: "Together.ai",
            isDefault: true,
            maxOutputTokens: 32_000
        ),
        AIModel(
            id: "meta-llama/Meta-Llama-3-8B-Instruct-Lite",
            displayName: "Llama 3 8B Lite",
            description: "Cost-effective option",
            pricing: "$0.10/1M tokens",
            provider: "Together.ai"
        ),
        AIModel(
            id: "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo",
            displayName: "Llama 3.1 8B Turbo",
            description: "Good balance",
            pricing: "$0.18/1M tokens",
            provider: "Together.ai"
        ),
        AIModel(
            id: "Qwen/Qwen2.5-7B-Instruct-Turbo",
            displayName: "Qwen 2.5 7B Turbo",
            description: "Fast coding specialist",
            pricing: "$0.30/1M tokens",
            provider: "Together.ai"
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

        // Model-specific max tokens
        let maxTokens: Int
        if model.hasPrefix("zai-org/") || model.hasPrefix("moonshotai/") {
            maxTokens = 32_000
        } else if model.contains("Llama-3.1") || model.contains("Llama-3-") {
            maxTokens = 16_000
        } else {
            maxTokens = 8_000
        }
        let temperature = SamplingLimits.temperature(temperature, model: model)
        let topP = SamplingLimits.topP(topP, model: model)

        let body: [String: Any] = [
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
