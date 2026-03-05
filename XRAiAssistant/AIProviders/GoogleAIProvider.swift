import Foundation

class GoogleAIProvider: AIProvider {
    let name = "Google AI"
    let requiresAPIKey = true

    private var apiKey: String?
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    let capabilities = AIProviderCapabilities(
        supportsVision: true,
        supportsStreaming: true,
        supportedImageFormats: ["image/jpeg", "image/png", "image/webp"],
        maxImageSize: 4 * 1024 * 1024,  // 4MB
        maxImagesPerMessage: 16,
        maxTokens: 1_000_000  // Gemini 2.5 Pro context
    )

    let models: [AIModel] = [
        // Gemini 3 Series (Newest & Most Powerful)
        AIModel(
            id: "gemini-3.1-pro-preview",
            displayName: "Gemini 3.1 Pro",
            description: "Newest and most powerful general-purpose model - top-tier reasoning, writing, planning, coding, multimodal understanding",
            pricing: "FREE tier available",
            provider: "Google AI",
            isDefault: true,
            supportsVision: true
        ),

        // Gemini 2.5 Series (Latest Stable)
        AIModel(
            id: "gemini-2.5-pro",
            displayName: "Gemini 2.5 Pro",
            description: "High-capability reasoning & coding - strong for complex codebases, algorithmic tasks, data/maths logic",
            pricing: "FREE tier available",
            provider: "Google AI",
            supportsVision: true
        ),
        AIModel(
            id: "gemini-2.5-flash",
            displayName: "Gemini 2.5 Flash",
            description: "Balanced - lower latency & snappier, supports coding & writing - good for general use and prototyping",
            pricing: "FREE tier available",
            provider: "Google AI",
            supportsVision: true
        ),
        AIModel(
            id: "gemini-2.5-flash-lite",
            displayName: "Gemini 2.5 Flash-Lite",
            description: "Lightweight and fastest - optimized for speed and shorter tasks",
            pricing: "FREE tier available",
            provider: "Google AI",
            supportsVision: true
        )
    ]

    func configure(apiKey: String) {
        self.apiKey = apiKey
        print("🔧 Google AI provider configured with API key: \(String(apiKey.prefix(10)))...")
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

        // Convert messages to Gemini format
        var contents: [[String: Any]] = []
        var systemInstruction: String = ""

        for message in messages {
            if message.role == .system {
                systemInstruction = message.textContent
            } else {
                contents.append(convertMessageToGeminiFormat(message))
            }
        }

        var requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": temperature,
                "topP": topP,
                "maxOutputTokens": 65536
            ]
        ]

        if !systemInstruction.isEmpty {
            requestBody["systemInstruction"] = [
                "parts": [["text": systemInstruction]]
            ]
        }

        print("🚀 Google AI request: model=\(model), temp=\(temperature), top-p=\(topP)")

        return AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    // Use streamGenerateContent with alt=sse for SSE streaming
                    guard let url = URL(string: "\(baseURL)/models/\(model):streamGenerateContent?key=\(apiKey)&alt=sse") else {
                        throw AIProviderError.configurationError("Invalid URL")
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

                    print("📤 Sending request to Google AI...")

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

                    print("📥 Receiving Google AI SSE stream...")

                    var lineBuffer = ""
                    var totalTextYielded = 0

                    for try await byte in asyncBytes {
                        let char = Character(UnicodeScalar(byte))

                        if char == "\n" {
                            let line = lineBuffer.trimmingCharacters(in: .whitespaces)
                            lineBuffer = ""

                            if line.hasPrefix("data: ") {
                                let jsonString = String(line.dropFirst(6))

                                if let jsonData = jsonString.data(using: .utf8),
                                   let chunk = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                   let candidates = chunk["candidates"] as? [[String: Any]],
                                   let firstCandidate = candidates.first,
                                   let content = firstCandidate["content"] as? [String: Any],
                                   let parts = content["parts"] as? [[String: Any]],
                                   let firstPart = parts.first,
                                   let text = firstPart["text"] as? String {
                                    totalTextYielded += text.count
                                    continuation.yield(text)
                                }
                            }
                        } else {
                            lineBuffer.append(char)
                        }
                    }

                    print("🏁 Google AI stream complete (\(totalTextYielded) total chars yielded)")
                    continuation.finish()
                } catch {
                    print("❌ Google AI error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Message Conversion

    private func convertMessageToGeminiFormat(_ message: AIMessage) -> [String: Any] {
        var parts: [[String: Any]] = []

        for contentItem in message.content {
            switch contentItem {
            case .text(let text):
                parts.append(["text": text])

            case .image(let imageContent):
                parts.append([
                    "inline_data": [
                        "mime_type": imageContent.mimeType,
                        "data": imageContent.base64String
                    ]
                ])
            }
        }

        return [
            "role": mapRole(message.role),
            "parts": parts
        ]
    }

    private func mapRole(_ role: AIMessageRole) -> String {
        switch role {
        case .system: return "system" // Handled separately as systemInstruction
        case .user: return "user"
        case .assistant: return "model" // Gemini uses "model" instead of "assistant"
        }
    }
}
