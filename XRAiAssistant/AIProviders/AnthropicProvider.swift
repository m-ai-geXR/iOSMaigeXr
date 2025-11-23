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
        maxTokens: 200_000  // Claude 3.5 context window
    )

    let models: [AIModel] = [
        // Claude 4.5 Series (Latest - 2025)
        AIModel(
            id: "claude-sonnet-4-5-20250929",
            displayName: "Claude Sonnet 4.5",
            description: "Smartest model for complex agents and coding - 200K context",
            pricing: "$3.00/$15.00 per 1M tokens",
            provider: "Anthropic",
            isDefault: true,
            supportsVision: true
        ),
        AIModel(
            id: "claude-haiku-4-5-20251001",
            displayName: "Claude Haiku 4.5",
            description: "Fastest model with near-frontier intelligence - 200K context",
            pricing: "$0.25/$1.25 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true
        ),

        // Claude 4.1 Series
        AIModel(
            id: "claude-opus-4-1-20250805",
            displayName: "Claude Opus 4.1",
            description: "Exceptional model for specialized reasoning tasks - 200K context",
            pricing: "$15.00/$75.00 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true
        ),

        // Claude 4 Series (May 2025)
        AIModel(
            id: "claude-sonnet-4-20250514",
            displayName: "Claude Sonnet 4",
            description: "Previous Sonnet 4 version - 200K context",
            pricing: "$3.00/$15.00 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true
        ),
        AIModel(
            id: "claude-opus-4-20250514",
            displayName: "Claude Opus 4",
            description: "Previous Opus 4 version - 200K context",
            pricing: "$15.00/$75.00 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true
        ),

        // Claude 3.5 Series (Legacy - 2024)
        AIModel(
            id: "claude-3-5-sonnet-20241022",
            displayName: "Claude 3.5 Sonnet (Oct 2024)",
            description: "Previous generation high-performance model",
            pricing: "$3.00/$15.00 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true
        ),
        AIModel(
            id: "claude-3-5-sonnet-20240620",
            displayName: "Claude 3.5 Sonnet (June 2024)",
            description: "Earlier 3.5 Sonnet version",
            pricing: "$3.00/$15.00 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true
        ),
        AIModel(
            id: "claude-3-5-haiku-20241022",
            displayName: "Claude 3.5 Haiku",
            description: "Fast and affordable legacy model",
            pricing: "$0.25/$1.25 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true
        ),

        // Claude 3 Series (Legacy - Early 2024)
        AIModel(
            id: "claude-3-opus-20240229",
            displayName: "Claude 3 Opus",
            description: "Original powerful model",
            pricing: "$15.00/$75.00 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true
        ),
        AIModel(
            id: "claude-3-sonnet-20240229",
            displayName: "Claude 3 Sonnet",
            description: "Original balanced model",
            pricing: "$3.00/$15.00 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true
        ),
        AIModel(
            id: "claude-3-haiku-20240307",
            displayName: "Claude 3 Haiku",
            description: "Original fast model",
            pricing: "$0.25/$1.25 per 1M tokens",
            provider: "Anthropic",
            supportsVision: true
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
        topP: Double
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

        // Build request body
        var requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": anthropicMessages,
            "stream": true
        ]

        // Claude 4 series models don't support both temperature and top_p simultaneously
        // Use only temperature for Claude 4.x models
        if model.contains("claude-sonnet-4") || model.contains("claude-opus-4") || model.contains("claude-haiku-4") {
            requestBody["temperature"] = temperature
        } else {
            // Claude 3.x models support both parameters
            requestBody["temperature"] = temperature
            requestBody["top_p"] = topP
        }

        if let systemPrompt = systemPrompt {
            requestBody["system"] = systemPrompt
        }

        print("🚀 Anthropic request: model=\(model), temp=\(temperature), top-p=\(topP)")

        return AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    guard let url = URL(string: "\(baseURL)/messages") else {
                        throw AIProviderError.configurationError("Invalid URL")
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
                                        }
                                    }
                                }
                            }

                            buffer = ""
                        }
                    }

                    print("🏁 Anthropic stream complete")
                    continuation.finish()
                } catch {
                    print("❌ Anthropic error: \(error)")
                    continuation.finish(throwing: error)
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
