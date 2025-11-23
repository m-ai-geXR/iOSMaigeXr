import Foundation

// MARK: - Message Content Types

enum AIMessageContentType {
    case text(String)
    case image(AIImageContent)
}

struct AIImageContent {
    let data: Data
    let mimeType: String  // "image/jpeg", "image/png", "image/webp"
    let filename: String?

    var base64String: String {
        return data.base64EncodedString()
    }
}

// MARK: - Universal Message Format

struct AIMessage {
    let role: AIMessageRole
    let content: [AIMessageContentType]
    let timestamp: Date
    let id: String

    // Convenience initializers
    init(role: AIMessageRole, text: String) {
        self.role = role
        self.content = [.text(text)]
        self.timestamp = Date()
        self.id = UUID().uuidString
    }

    init(role: AIMessageRole, content: [AIMessageContentType]) {
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.id = UUID().uuidString
    }

    init(role: AIMessageRole, content: [AIMessageContentType], timestamp: Date, id: String) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.id = id
    }

    // Helper to get text-only content
    var textContent: String {
        content.compactMap {
            if case .text(let text) = $0 { return text }
            return nil
        }.joined(separator: "\n")
    }

    var hasImages: Bool {
        content.contains { if case .image = $0 { return true } else { return false } }
    }
}

enum AIMessageRole {
    case system
    case user
    case assistant
}

// MARK: - Provider Capabilities

struct AIProviderCapabilities {
    let supportsVision: Bool
    let supportsStreaming: Bool
    let supportedImageFormats: [String]
    let maxImageSize: Int  // in bytes
    let maxImagesPerMessage: Int
    let maxTokens: Int
}

// MARK: - AI Provider Protocol

protocol AIProvider: AnyObject {
    var name: String { get }
    var models: [AIModel] { get }
    var requiresAPIKey: Bool { get }
    var capabilities: AIProviderCapabilities { get }

    func configure(apiKey: String)
    func generateResponse(
        messages: [AIMessage],
        model: String,
        temperature: Double,
        topP: Double
    ) async throws -> AsyncThrowingStream<String, Error>
}

// MARK: - Model Definition

struct AIModel {
    let id: String
    let displayName: String
    let description: String
    let pricing: String
    let provider: String
    let isDefault: Bool
    let supportsVision: Bool

    init(
        id: String,
        displayName: String,
        description: String,
        pricing: String = "",
        provider: String,
        isDefault: Bool = false,
        supportsVision: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.pricing = pricing
        self.provider = provider
        self.isDefault = isDefault
        self.supportsVision = supportsVision
    }
}

// MARK: - Provider Configuration

struct ProviderConfiguration {
    let apiKey: String
    let baseURL: String?
    let defaultModel: String
    let supportedParameters: Set<AIParameter>
}

enum AIParameter {
    case temperature
    case topP
    case maxTokens
    case stream
}

// MARK: - Error Handling

enum AIProviderError: Error, LocalizedError {
    case invalidAPIKey
    case modelNotSupported
    case rateLimitExceeded
    case networkError(String)
    case responseEmpty
    case configurationError(String)
    case imageNotSupported(String)
    case imageTooLarge(Int, Int)
    case invalidImageFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key provided"
        case .modelNotSupported:
            return "Model not supported by this provider"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .networkError(let message):
            return "Network error: \(message)"
        case .responseEmpty:
            return "Empty response received"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .imageNotSupported(let provider):
            return "\(provider) does not support image inputs"
        case .imageTooLarge(let size, let max):
            return "Image too large (\(size) bytes). Max: \(max) bytes"
        case .invalidImageFormat(let format):
            return "Invalid image format: \(format)"
        }
    }
}