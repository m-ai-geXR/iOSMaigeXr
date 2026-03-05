import Foundation

class XAIProvider: AIProvider {
    let name = "xAI"
    let requiresAPIKey = true

    private var apiKey: String?
    private let baseURL = "https://api.x.ai/v1"

    let capabilities = AIProviderCapabilities(
        supportsVision: false,
        supportsStreaming: true,
        supportedImageFormats: [],
        maxImageSize: 0,
        maxImagesPerMessage: 0,
        maxTokens: 131_072  // Grok context window
    )

    let models: [AIModel] = [
        // Grok 4 Series (Latest)
        AIModel(
            id: "grok-4-0709",
            displayName: "Grok 4",
            description: "Latest and most capable Grok model - advanced reasoning and coding",
            pricing: "xAI API pricing",
            provider: "xAI",
            isDefault: true,
            supportsVision: false
        ),
        AIModel(
            id: "grok-4-fast-reasoning",
            displayName: "Grok 4 Fast Reasoning",
            description: "Fast Grok 4 with enhanced reasoning capabilities",
            pricing: "xAI API pricing",
            provider: "xAI",
            supportsVision: false
        ),

        // Grok 3 Series
        AIModel(
            id: "grok-3",
            displayName: "Grok 3",
            description: "Powerful general-purpose model with strong coding and analysis",
            pricing: "xAI API pricing",
            provider: "xAI",
            supportsVision: false
        ),
        AIModel(
            id: "grok-3-mini",
            displayName: "Grok 3 Mini",
            description: "Lightweight Grok 3 for faster responses and lower cost",
            pricing: "xAI API pricing",
            provider: "xAI",
            supportsVision: false
        ),
        AIModel(
            id: "grok-code-fast-1",
            displayName: "Grok Code Fast",
            description: "Specialized fast model optimized for coding tasks",
            pricing: "xAI API pricing",
            provider: "xAI",
            supportsVision: false
        )
    ]

    func configure(apiKey: String) {
        self.apiKey = apiKey
        print("🔧 xAI provider configured with API key: \(String(apiKey.prefix(10)))...")
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

        let xaiMessages = messages.map { message in
            convertMessageToOpenAIFormat(message)
        }

        let requestBody: [String: Any] = [
            "model": model,
            "messages": xaiMessages,
            "temperature": temperature,
            "top_p": topP,
            "max_tokens": 32768,
            "stream": true
        ]

        print("🚀 xAI request: model=\(model), temp=\(temperature), top-p=\(topP)")

        return AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    guard let url = URL(string: "\(self.baseURL)/chat/completions") else {
                        throw AIProviderError.configurationError("Invalid URL")
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

                    print("📥 Receiving xAI streaming response...")

                    var lineBuffer = ""

                    for try await byte in asyncBytes {
                        let char = Character(UnicodeScalar(byte))

                        if char == "\n" {
                            let line = lineBuffer.trimmingCharacters(in: .whitespaces)
                            lineBuffer = ""

                            if line.hasPrefix("data: ") {
                                let jsonString = String(line.dropFirst(6))

                                if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                                    continuation.finish()
                                    return
                                }

                                if let jsonData = jsonString.data(using: .utf8),
                                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                   let choices = json["choices"] as? [[String: Any]],
                                   let delta = choices.first?["delta"] as? [String: Any],
                                   let content = delta["content"] as? String {
                                    continuation.yield(content)
                                }
                            }
                        } else {
                            lineBuffer.append(char)
                        }
                    }

                    continuation.finish()
                } catch {
                    print("❌ xAI error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Message Conversion

    private func convertMessageToOpenAIFormat(_ message: AIMessage) -> [String: Any] {
        var openAIMessage: [String: Any] = [
            "role": mapRole(message.role)
        ]

        if message.content.count == 1, case .text(let text) = message.content[0] {
            openAIMessage["content"] = text
        } else {
            var contentArray: [[String: Any]] = []
            for contentItem in message.content {
                switch contentItem {
                case .text(let text):
                    contentArray.append(["type": "text", "text": text])
                case .image:
                    break // xAI does not support vision in current models
                }
            }
            openAIMessage["content"] = contentArray
        }

        return openAIMessage
    }

    private func mapRole(_ role: AIMessageRole) -> String {
        switch role {
        case .system: return "system"
        case .user: return "user"
        case .assistant: return "assistant"
        }
    }
}
