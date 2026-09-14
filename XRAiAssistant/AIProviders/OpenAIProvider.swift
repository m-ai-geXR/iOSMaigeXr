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
        maxTokens: 1_050_000  // GPT-5.6 / GPT-6 context (1.05M tokens)
    )

    let models: [AIModel] = [
        // GPT-6 Series (current generation)
        AIModel(
            id: "gpt-6-astra",
            displayName: "GPT-6 Astra",
            description: "Most capable model, built for the hardest end-to-end work - 1.05M context",
            pricing: "$10.00/$50.00 per 1M tokens",
            provider: "OpenAI",
            supportsVision: true,
            control: .effort,
            maxOutputTokens: 64_000
        ),

        // GPT-5.6 Series (current generation)
        AIModel(
            id: "gpt-5.6-sol",
            displayName: "GPT-5.6 Sol",
            description: "Flagship for complex professional work - 1.05M context",
            pricing: "$4.00/$20.00 per 1M tokens",
            provider: "OpenAI",
            isDefault: true,
            supportsVision: true,
            control: .effort,
            maxOutputTokens: 64_000
        ),
        AIModel(
            id: "gpt-5.6-terra",
            displayName: "GPT-5.6 Terra",
            description: "Balances intelligence and cost - 1.05M context",
            pricing: "$2.00/$12.00 per 1M tokens",
            provider: "OpenAI",
            supportsVision: true,
            control: .effort,
            maxOutputTokens: 64_000
        ),
        AIModel(
            id: "gpt-5.6-luna",
            displayName: "GPT-5.6 Luna",
            description: "Optimized for cost-sensitive workloads - 1.05M context",
            pricing: "$0.20/$1.20 per 1M tokens",
            provider: "OpenAI",
            supportsVision: true,
            control: .effort,
            maxOutputTokens: 64_000
        ),

        // GPT-5.2 (previous generation - kept as fallback)
        AIModel(
            id: "gpt-5.2",
            displayName: "GPT-5.2",
            description: "Previous-generation coding and agentic model - 400K context",
            pricing: "$1.75/$14.00 per 1M tokens",
            provider: "OpenAI",
            supportsVision: true,
            control: .sampling,
            maxOutputTokens: 64_000
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
        topP: Double,
        effort: AIEffort
    ) async throws -> AsyncThrowingStream<String, Error> {

        guard let apiKey = apiKey else {
            throw AIProviderError.configurationError("Provider not configured with API key")
        }

        let openAIMessages = messages.map { message in
            convertMessageToOpenAIFormat(message)
        }

        let definition = models.first { $0.id == model }
        let maxTokens = definition?.maxOutputTokens ?? 16_000
        let control = definition?.control ?? .sampling

        var requestBody: [String: Any] = [
            "model": model,
            "messages": openAIMessages,
            "stream": true
        ]

        switch control {
        case .effort:
            // GPT-5.6 / GPT-6 accept only the default temperature and top_p, and
            // renamed the output cap. Sending the old fields is a 400.
            requestBody["reasoning_effort"] = effort.rawValue
            requestBody["max_completion_tokens"] = maxTokens
        case .sampling:
            requestBody["temperature"] = temperature
            requestBody["top_p"] = topP
            requestBody["max_tokens"] = maxTokens
        }

        let controlLog = control == .effort
            ? "effort=\(effort.rawValue)"
            : "temp=\(temperature), top-p=\(topP)"
        print("🚀 OpenAI request: model=\(model), \(controlLog), max-tokens=\(maxTokens)")
        
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