import Foundation
import AIProxy

class TogetherAIProvider: AIProvider {
    let name = "Together.ai"
    let requiresAPIKey = true

    private var togetherAIService: TogetherAIService?
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
        self.togetherAIService = AIProxy.togetherAIDirectService(
            unprotectedAPIKey: apiKey
        )
        print("🔧 Together.ai provider configured")
    }
    
    func generateResponse(
        messages: [AIMessage],
        model: String,
        temperature: Double,
        topP: Double,
        effort: AIEffort
    ) async throws -> AsyncThrowingStream<String, Error> {
        
        guard let service = togetherAIService else {
            throw AIProviderError.configurationError("Provider not configured with API key")
        }
        
        // Convert messages to Together.ai format - using the same pattern as ChatViewModel
        let togetherMessages = messages.map { message in
            switch message.role {
            case .system:
                return TogetherAIMessage(content: message.textContent, role: .system)
            case .user:
                return TogetherAIMessage(content: message.textContent, role: .user)
            case .assistant:
                return TogetherAIMessage(content: message.textContent, role: .assistant)
            }
        }
        
        // Model-specific max tokens
        // DeepSeek R1 and Llama 3.3 70B support 32K+ output, smaller models 8-16K
        let maxTokens: Int
        if model.contains("DeepSeek-R1") || model.contains("Llama-3.3-70B") {
            maxTokens = 32_000  // Large models support 32K output
        } else if model.contains("Llama-3.1") || model.contains("Llama-3-") {
            maxTokens = 16_000  // Medium Llama models support 16K
        } else if model.contains("Qwen") {
            maxTokens = 8_000   // Qwen models typically 8K
        } else {
            maxTokens = 8_000   // Safe default for other models
        }

        let requestBody = TogetherAIChatCompletionRequestBody(
            messages: togetherMessages,
            model: model,
            maxTokens: maxTokens,
            stream: true,
            temperature: temperature,
            topP: topP
        )

        print("🚀 Together.ai request: model=\(model), temp=\(temperature), top-p=\(topP), max-tokens=\(maxTokens)")
        
        return AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    let streamingResponse = try await service.streamingChatCompletionRequest(body: requestBody)
                    
                    for try await chunk in streamingResponse {
                        if let content = chunk.choices.first?.delta.content {
                            continuation.yield(content)
                        }
                        
                        if let finishReason = chunk.choices.first?.finishReason {
                            print("🏁 Together.ai stream finished: \(finishReason)")
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    print("❌ Together.ai error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}