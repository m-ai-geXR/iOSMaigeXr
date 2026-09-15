import Foundation

class AnthropicProvider: AIProvider {
    let name = "Anthropic"
    let requiresAPIKey = true

    private var apiKey: String?
    private let baseURL = "https://api.anthropic.com/v1"
    private let apiVersion = "2023-06-01"

    let capabilities = AIProviderCapabilities(
        supportsVision: true,
        supportsStreaming: true,
        supportedImageFormats: ["image/jpeg", "image/png", "image/gif", "image/webp"],
        maxImageSize: 5 * 1024 * 1024,  // 5MB
        maxImagesPerMessage: 20,
        maxTokens: 1_000_000  // Claude 5 series context window (1M)
    )

    let models: [AIModel] = [
        // Claude 5 Series (current generation)
        AIModel(
            id: "claude-fable-5-1",
            displayName: "Claude Fable 5.1",
            description: "Most capable model for the hardest reasoning and agentic work - 1M context",
            pricing: "$10.00/$50.00 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true,
            control: .effort,
            maxOutputTokens: 64_000
        ),
        AIModel(
            id: "claude-opus-5",
            displayName: "Claude Opus 5",
            description: "Frontier intelligence for agents and coding - 1M context",
            pricing: "$5.00/$25.00 per 1M tokens",
            provider: "Anthropic",
            isDefault: true,
            supportsVision: true,
            control: .effort,
            maxOutputTokens: 64_000
        ),
        AIModel(
            id: "claude-sonnet-5",
            displayName: "Claude Sonnet 5",
            description: "Best combination of speed, cost and intelligence - 1M context",
            pricing: "$2.00/$10.00 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true,
            control: .effort,
            maxOutputTokens: 64_000
        ),
        AIModel(
            id: "claude-haiku-4-5",
            displayName: "Claude Haiku 4.5",
            description: "Fastest model with near-frontier intelligence - 200K context",
            pricing: "$1.00/$5.00 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true,
            control: .sampling,
            maxOutputTokens: 32_000
        ),

        // Claude 4.6 Series (previous generation - kept as fallback)
        AIModel(
            id: "claude-opus-4-6",
            displayName: "Claude Opus 4.6",
            description: "Previous-generation flagship - 200K/1M context",
            pricing: "$5.00/$25.00 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true,
            control: .sampling,
            maxOutputTokens: 64_000
        ),
        AIModel(
            id: "claude-sonnet-4-6",
            displayName: "Claude Sonnet 4.6",
            description: "Previous-generation balanced model - 200K/1M context",
            pricing: "$3.00/$15.00 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true,
            control: .sampling,
            maxOutputTokens: 64_000
        )
    ]

    func configure(apiKey: String) {
        self.apiKey = apiKey
        print("🔧 Anthropic provider configured with API key: \(String(apiKey.prefix(10)))...")
    }

    func generateResponse(
        messages: [AIMessage],
        model: String,
        temperature: Double,
        topP: Double,
        effort: AIEffort
    ) async throws -> AsyncThrowingStream<String, Error> {

        guard let apiKey = apiKey else {
            throw AIProviderError.configurationError("Provider not configured with API key")
        }

        // Convert messages to Anthropic format
        var anthropicMessages: [[String: Any]] = []
        var systemPrompt: String? = nil

        for message in messages {
            if message.role == .system {
                // Anthropic uses separate system parameter
                systemPrompt = message.textContent
            } else {
                anthropicMessages.append(convertMessageToAnthropicFormat(message))
            }
        }

        let definition = models.first { $0.id == model }
        let maxTokens = definition?.maxOutputTokens ?? 16_000
        let control = definition?.control ?? .sampling

        var requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": anthropicMessages,
            "stream": true
        ]

        switch control {
        case .effort:
            // Claude 5 series removed temperature/top_p — sending either is a 400.
            requestBody["output_config"] = ["effort": effort.rawValue]
            requestBody["thinking"] = ["type": "adaptive"]
        case .sampling:
            // Claude 4.x rejects temperature and top_p together; temperature alone is valid.
            requestBody["temperature"] = temperature
        }

        if let systemPrompt = systemPrompt {
            requestBody["system"] = systemPrompt
        }

        let controlLog = control == .effort ? "effort=\(effort.rawValue)" : "temp=\(temperature)"
        print("🚀 Anthropic request: model=\(model), \(controlLog), max-tokens=\(maxTokens)")

        return AsyncThrowingStream<String, Error> { continuation in
            Task {
                var attempt = 0

                while true {
                    // Replaying a request after content already reached the consumer
                    // would duplicate text, so only an attempt that yielded nothing
                    // may be retried.
                    var yieldedContent = false

                    do {
                        guard let url = URL(string: "\(baseURL)/messages") else {
                            throw AIProviderError.configurationError("Invalid URL")
                        }

                        var request = URLRequest(url: url)
                        request.httpMethod = "POST"
                        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        // Adaptive thinking can run for minutes before the first token.
                        // URLSession's 60s default is an inactivity timeout and trips
                        // during that silence.
                        request.timeoutInterval = 600
                        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

                        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

                        if let httpResponse = response as? HTTPURLResponse {
                            print("📡 HTTP Status: \(httpResponse.statusCode)")
                            guard httpResponse.statusCode == 200 else {
                                var errorBody = ""
                                for try await byte in asyncBytes {
                                    errorBody.append(Character(UnicodeScalar(byte)))
                                }
                                print("❌ Error response: \(errorBody)")
                                throw AIProviderError.networkError("HTTP \(httpResponse.statusCode): \(errorBody)")
                            }
                        }

                        print("📥 Receiving streaming response...")

                        var buffer = ""

                        for try await byte in asyncBytes {
                            let char = Character(UnicodeScalar(byte))
                            buffer.append(char)

                            // Anthropic SSE format: "data: {...}\n\n"
                            if buffer.hasSuffix("\n\n") {
                                let lines = buffer.components(separatedBy: "\n")

                                for line in lines {
                                    if line.hasPrefix("data: ") {
                                        let jsonString = String(line.dropFirst(6))

                                        if let jsonData = jsonString.data(using: .utf8),
                                           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                           let type = json["type"] as? String {

                                            // Extract text from content_block_delta events
                                            if type == "content_block_delta",
                                               let delta = json["delta"] as? [String: Any],
                                               let deltaType = delta["type"] as? String,
                                               deltaType == "text_delta",
                                               let text = delta["text"] as? String {
                                                continuation.yield(text)
                                                yieldedContent = true
                                            }
                                        }
                                    }
                                }

                                buffer = ""
                            }
                        }

                        print("🏁 Anthropic stream complete")
                        continuation.finish()
                        return
                    } catch {
                        let canRetry = !yieldedContent
                            && attempt < AIRetry.maxAttempts
                            && AIRetry.isTransient(error)

                        guard canRetry else {
                            print("❌ Anthropic error: \(error)")
                            continuation.finish(throwing: error)
                            return
                        }

                        print("⚠️ Anthropic transient failure (attempt \(attempt + 1)/\(AIRetry.maxAttempts)), retrying: \(error.localizedDescription)")
                        try? await Task.sleep(nanoseconds: AIRetry.backoffNanoseconds(attempt: attempt))
                        attempt += 1
                    }
                }
            }
        }
    }

    // MARK: - Message Conversion

    private func convertMessageToAnthropicFormat(_ message: AIMessage) -> [String: Any] {
        var anthropicMessage: [String: Any] = [
            "role": mapRole(message.role)
        ]

        // Check if message has multiple content types or images
        if message.content.count == 1, case .text(let text) = message.content[0] {
            // Simple text-only message
            anthropicMessage["content"] = text
        } else {
            // Multimodal message (text + images or multiple content blocks)
            var contentArray: [[String: Any]] = []

            for contentItem in message.content {
                switch contentItem {
                case .text(let text):
                    contentArray.append([
                        "type": "text",
                        "text": text
                    ])

                case .image(let imageContent):
                    contentArray.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": imageContent.mimeType,
                            "data": imageContent.base64String
                        ]
                    ])
                }
            }

            anthropicMessage["content"] = contentArray
        }

        return anthropicMessage
    }

    private func mapRole(_ role: AIMessageRole) -> String {
        switch role {
        case .system: return "system"  // Handled separately
        case .user: return "user"
        case .assistant: return "assistant"
        }
    }
}
