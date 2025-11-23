import Foundation

class GoogleAIProvider: AIProvider {
    let name = "Google AI"
    let requiresAPIKey = true

    private var apiKey: String?
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    let models: [AIModel] = [
        // Gemini 3.0 Series (Preview)
        AIModel(
            id: "gemini-3.0-flash",
            displayName: "Gemini 3.0 Flash",
            description: "Next-generation flash model",
            pricing: "FREE tier available",
            provider: "Google AI",
            isDefault: true
        ),

        // Gemini 2.5 Series (Latest Stable)
        AIModel(
            id: "gemini-2.5-flash",
            displayName: "Gemini 2.5 Flash",
            description: "Fast model with improved performance",
            pricing: "FREE tier available",
            provider: "Google AI"
        ),
        AIModel(
            id: "gemini-2.5-pro",
            displayName: "Gemini 2.5 Pro",
            description: "Most capable model with advanced reasoning",
            pricing: "FREE tier available",
            provider: "Google AI"
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
                systemInstruction = message.content
            } else {
                contents.append([
                    "role": mapRole(message.role),
                    "parts": [["text": message.content]]
                ])
            }
        }

        var requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": temperature,
                "topP": topP,
                "maxOutputTokens": 8000
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
                    // Use streamGenerateContent endpoint for streaming
                    guard let url = URL(string: "\(baseURL)/models/\(model):streamGenerateContent?key=\(apiKey)") else {
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

                    print("📥 Receiving streaming response...")

                    var fullResponse = ""
                    var totalTextYielded = 0

                    // Accumulate all bytes into full response
                    for try await byte in asyncBytes {
                        fullResponse.append(Character(UnicodeScalar(byte)))
                    }

                    print("📊 Received \(fullResponse.count) total bytes")

                    // Parse as JSON array
                    if let jsonData = fullResponse.data(using: .utf8),
                       let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {

                        print("✅ Parsed JSON array with \(jsonArray.count) chunks")

                        // Process each chunk and extract text
                        for (index, chunk) in jsonArray.enumerated() {
                            if let candidates = chunk["candidates"] as? [[String: Any]],
                               let firstCandidate = candidates.first,
                               let content = firstCandidate["content"] as? [String: Any],
                               let parts = content["parts"] as? [[String: Any]],
                               let firstPart = parts.first,
                               let text = firstPart["text"] as? String {

                                print("📦 Chunk \(index + 1): Yielding \(text.count) chars")
                                totalTextYielded += text.count
                                continuation.yield(text)
                            }
                        }
                    } else {
                        print("❌ Failed to parse response as JSON array")
                        print("📄 Response preview (first 500 chars): \(String(fullResponse.prefix(500)))")
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

    private func mapRole(_ role: AIMessageRole) -> String {
        switch role {
        case .system: return "system" // Handled separately as systemInstruction
        case .user: return "user"
        case .assistant: return "model" // Gemini uses "model" instead of "assistant"
        }
    }
}
