import Foundation

class OpenAIProvider: AIProvider {
    let name = "OpenAI"
    let requiresAPIKey = true

    private var apiKey: String?
    private let baseURL = "https://api.openai.com/v1"

    let capabilities = AIProviderCapabilities(
        supportsVision: true,
        supportsStreaming: true,
        supportedImageFormats: ["image/jpeg", "image/png", "image/webp", "image/gif"],
        maxImageSize: 20 * 1024 * 1024,  // 20MB
        maxImagesPerMessage: 10,
        maxTokens: 400_000  // GPT-5.2 context (400K tokens)
    )

    let models: [AIModel] = [
        // GPT-5.2 Series (Latest - December 2025)
        AIModel(
            id: "gpt-5.2",
            displayName: "GPT-5.2",
            description: "Best model for coding and agentic tasks",
            pricing: "$1.75/$14.00 per 1M tokens",
            provider: "OpenAI",
            isDefault: true,
            supportsVision: true
        ),
        AIModel(
            id: "gpt-5.2-pro",
            displayName: "GPT-5.2 Pro",
            description: "Smartest and most trustworthy - highest accuracy",
            pricing: "Premium tier",
            provider: "OpenAI",
            supportsVision: true
        ),
        AIModel(
            id: "gpt-5.2-chat-latest",
            displayName: "GPT-5.2 Chat (Latest)",
            description: "Latest ChatGPT model with automatic updates",
            pricing: "$1.75/$14.00 per 1M tokens",
            provider: "OpenAI",
            supportsVision: true
        ),

        // Reasoning Models (o-series)
        AIModel(
            id: "o1-2024-12-17",
            displayName: "o1",
            description: "Advanced reasoning model for complex problems",
            pricing: "Premium tier",
            provider: "OpenAI",
            supportsVision: false
        ),
        AIModel(
            id: "o3-mini-2025-01-31",
            displayName: "o3-mini",
            description: "Latest reasoning model with enhanced reasoning abilities",
            pricing: "Economy tier",
            provider: "OpenAI",
            supportsVision: false
        ),

        // GPT-4o Series (Still Supported)
        AIModel(
            id: "gpt-4o",
            displayName: "GPT-4o",
            description: "Versatile high-intelligence flagship model",
            pricing: "$2.50/$10.00 per 1M tokens",
            provider: "OpenAI",
            supportsVision: true
        ),
        AIModel(
            id: "gpt-4o-mini",
            displayName: "GPT-4o Mini",
            description: "Fast and affordable small model for focused tasks",
            pricing: "$0.15/$0.60 per 1M tokens",
            provider: "OpenAI",
            supportsVision: true
        )
    ]
    
    func configure(apiKey: String) {
        self.apiKey = apiKey
        print("🔧 OpenAI provider configured with API key: \(String(apiKey.prefix(10)))...")
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
        
        let openAIMessages = messages.map { message in
            convertMessageToOpenAIFormat(message)
        }
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": openAIMessages,
            "temperature": temperature,
            "top_p": topP,
            "stream": true
        ]
        
        print("🚀 OpenAI request: model=\(model), temp=\(temperature), top-p=\(topP)")
        
        return AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    guard let url = URL(string: "\(baseURL)/chat/completions") else {
                        throw AIProviderError.configurationError("Invalid URL")
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                    
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        guard httpResponse.statusCode == 200 else {
                            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                            throw AIProviderError.networkError("HTTP \(httpResponse.statusCode): \(errorMessage)")
                        }
                    }
                    
                    let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []
                    
                    for line in lines {
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
                    }
                    continuation.finish()
                } catch {
                    print("❌ OpenAI error: \(error)")
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

        // Check if message has only text or multiple content types
        if message.content.count == 1, case .text(let text) = message.content[0] {
            // Simple text-only message
            openAIMessage["content"] = text
        } else {
            // Multimodal message (text + images)
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
                        "type": "image_url",
                        "image_url": [
                            "url": "data:\(imageContent.mimeType);base64,\(imageContent.base64String)"
                        ]
                    ])
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