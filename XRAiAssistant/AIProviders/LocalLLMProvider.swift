import Foundation

/// The user's own model server: Ollama, LM Studio, llama.cpp, vLLM or any
/// server that speaks the OpenAI chat completions API. The user enters its
/// address and model name in Settings; the API key is optional.
enum LocalServerConfig {
    static let providerName = "Local"
    static let modelPrefix = "local:"

    private static let baseURLKey = "XRAiAssistant_Local_BaseURL"
    private static let modelKey = "XRAiAssistant_Local_Model"

    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: baseURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: baseURLKey) }
    }

    static var modelName: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: modelKey) }
    }

    static var isConfigured: Bool {
        chatCompletionsURL(from: baseURL) != nil && !modelName.isEmpty
    }

    /// The chat completions endpoint for what the user typed. Accepts a bare host
    /// ("192.168.1.20:11434"), a server root ("http://mac.local:1234") or a URL
    /// that already ends in /v1 or /v1/chat/completions. Only http and https.
    static func chatCompletionsURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix("/chat/completions") {
            text.removeLast("/chat/completions".count)
        }
        if !text.hasSuffix("/v1") { text += "/v1" }
        guard let url = URL(string: text + "/chat/completions"),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// The model name sent to the server, from the app's prefixed model id.
    static func serverModelName(from modelId: String) -> String {
        modelId.hasPrefix(modelPrefix) ? String(modelId.dropFirst(modelPrefix.count)) : modelId
    }
}

final class LocalLLMProvider: AIProvider {
    let name = LocalServerConfig.providerName
    let requiresAPIKey = false

    private var apiKey: String?

    let capabilities = AIProviderCapabilities(
        supportsVision: false,
        supportsStreaming: true,
        supportedImageFormats: [],
        maxImageSize: 0,
        maxImagesPerMessage: 0,
        maxTokens: 32_768
    )

    /// One entry, the model named in Settings, or none until it is set up.
    var models: [AIModel] {
        let model = LocalServerConfig.modelName
        guard LocalServerConfig.isConfigured else { return [] }
        return [AIModel(
            id: LocalServerConfig.modelPrefix + model,
            displayName: model,
            description: "Your own server at \(LocalServerConfig.baseURL)",
            pricing: "Runs on your server",
            provider: name,
            isDefault: true,
            supportsVision: false
        )]
    }

    func configure(apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = (trimmed.isEmpty || trimmed == "changeMe") ? nil : trimmed
    }

    func generateResponse(
        messages: [AIMessage],
        model: String,
        temperature: Double,
        topP: Double,
        effort: AIEffort
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let url = LocalServerConfig.chatCompletionsURL(from: LocalServerConfig.baseURL) else {
            throw AIProviderError.configurationError("Local server address is not set. Add it in Settings.")
        }

        let body: [String: Any] = [
            "model": LocalServerConfig.serverModelName(from: model),
            "messages": messages.map(Self.openAIMessage),
            "temperature": temperature,
            "top_p": topP,
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300 // local models can be slow to start
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var errorBody = ""
                        for try await line in bytes.lines { errorBody += line }
                        throw AIProviderError.networkError("HTTP \(http.statusCode): \(errorBody)")
                    }
                    for try await line in bytes.lines {
                        guard let content = Self.content(fromStreamLine: line) else {
                            if line.trimmingCharacters(in: .whitespaces) == "data: [DONE]" { break }
                            continue
                        }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// The text in one server-sent event line, if it carries any.
    static func content(fromStreamLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String, !content.isEmpty else { return nil }
        return content
    }

    private static func openAIMessage(_ message: AIMessage) -> [String: Any] {
        let role: String
        switch message.role {
        case .system: role = "system"
        case .user: role = "user"
        case .assistant: role = "assistant"
        }
        let text = message.content.compactMap { item -> String? in
            if case .text(let value) = item { return value }
            return nil
        }.joined(separator: "\n")
        return ["role": role, "content": text]
    }
}
