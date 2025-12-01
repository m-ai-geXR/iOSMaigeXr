//
//  ChatViewModelRAGExtension.swift
//  XRAiAssistant
//
//  RAG integration for ChatViewModel
//  Adds semantic search and context-aware AI responses
//

import Foundation
import UIKit

extension ChatViewModel {

    // MARK: - RAG Services Initialization

    /// Initialize RAG services (call this after API key is configured)
    func initializeRAGServices() {
        let apiKey = aiProviderManager.getAPIKey(for: "Together.ai")
        guard apiKey != "changeMe" else {
            print("⚠️ RAG disabled: API key not configured")
            self.ragEnabled = false
            return
        }

        let embeddingService = EmbeddingService(apiKey: apiKey)
        let vectorSearchService = VectorSearchService(embeddingService: embeddingService)
        let ragContextBuilder = RAGContextBuilder(vectorSearch: vectorSearchService)

        self.embeddingService = embeddingService
        self.vectorSearchService = vectorSearchService
        self.ragContextBuilder = ragContextBuilder

        print("✅ RAG services initialized")
        self.ragEnabled = true
    }

    // MARK: - Enhanced Message Sending with RAG

    /// Send message with RAG context (call this instead of sendMessage when RAG is enabled)
    func sendMessageWithRAG(_ content: String, images: [UIImage] = []) async {
        guard ragEnabled, let ragBuilder = ragContextBuilder else {
            // Fall back to regular sendMessage or sendMessageWithImages
            if images.isEmpty {
                sendMessage(content)
            } else {
                sendMessageWithImages(content, images: images)
            }
            return
        }

        // Build RAG context
        var enhancedSystemPrompt = systemPrompt

        do {
            let ragContext = try await ragBuilder.buildContext(
                for: content,
                libraryId: library3DManager.selectedLibrary.id,
                topK: 10
            )

            if !ragContext.isEmpty {
                enhancedSystemPrompt = """
                \(systemPrompt)

                \(ragContext)

                **Instructions**: Use the context above to inform your responses when relevant. Reference specific examples from previous conversations when applicable. If the context doesn't help answer the question, rely on your general knowledge.
                """
                print("🎯 RAG context added to system prompt (\(ragContext.count) chars)")
            } else {
                print("ℹ️ No relevant RAG context found, using standard prompt")
            }
        } catch {
            print("⚠️ Failed to build RAG context: \(error)")
            // Continue without RAG context
        }

        // Send message with enhanced prompt
        await sendMessageWithCustomPrompt(content, images: images, customSystemPrompt: enhancedSystemPrompt)
    }

    /// Internal helper to send message with custom system prompt
    private func sendMessageWithCustomPrompt(_ content: String, images: [UIImage] = [], customSystemPrompt: String) async {
        // Add user message
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            content: content,
            isUser: true,
            timestamp: Date(),
            libraryId: library3DManager.selectedLibrary.id
        )

        await MainActor.run {
            messages.append(userMessage)
        }

        // Call AI with custom prompt
        do {
            let response = try await callLlamaInference(
                userMessage: content,
                systemPrompt: customSystemPrompt
            )

            let assistantMessage = ChatMessage(
                id: UUID().uuidString,
                content: response,
                isUser: false,
                timestamp: Date(),
                libraryId: library3DManager.selectedLibrary.id
            )

            await MainActor.run {
                messages.append(assistantMessage)
            }

            // Index new messages for future RAG queries (fire-and-forget)
            if ragEnabled {
                Task.detached { [weak self] in
                    await self?.indexNewMessages([userMessage, assistantMessage])
                }
            }

        } catch {
            print("❌ AI call failed: \(error)")
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Message Indexing

    /// Index new messages for RAG (background task)
    private func indexNewMessages(_ messages: [ChatMessage]) async {
        guard let embeddingService = embeddingService else { return }

        for message in messages {
            do {
                // Create RAG document
                let document = RAGDocument(
                    id: UUID().uuidString,
                    sourceType: "conversation",
                    sourceId: message.id,
                    chunkText: message.content,
                    chunkIndex: 0,
                    metadata: [
                        "library_id": message.libraryId ?? "",
                        "timestamp": ISO8601DateFormatter().string(from: message.timestamp)
                    ]
                )

                // Generate embedding
                let embedding = try await embeddingService.generateEmbedding(text: message.content)

                // Save to database
                try await DatabaseManager.shared.saveRAGDocument(document, embedding: embedding)

                print("✅ Indexed message for RAG: \(message.id.prefix(8))")
            } catch {
                print("⚠️ Failed to index message: \(error)")
            }
        }
    }

    // MARK: - Batch Indexing (for existing conversations)

    /// Index all existing conversations in background
    func indexAllConversations() async {
        guard ragEnabled, let embeddingService = embeddingService else {
            print("⚠️ RAG not enabled, cannot index conversations")
            return
        }

        print("🔄 Starting batch indexing of all conversations...")

        do {
            let conversations = try await DatabaseManager.shared.loadConversations(limit: 1000)
            var totalIndexed = 0

            for conversation in conversations {
                for message in conversation.messages {
                    // Skip if already indexed
                    // (In production, you'd check the database first)

                    do {
                        let document = RAGDocument(
                            id: UUID().uuidString,
                            sourceType: "conversation",
                            sourceId: conversation.id.uuidString,
                            chunkText: message.content,
                            chunkIndex: 0,
                            metadata: [
                                "library_id": message.libraryId ?? "",
                                "conversation_title": conversation.title
                            ]
                        )

                        let embedding = try await embeddingService.generateEmbedding(text: message.content)
                        try await DatabaseManager.shared.saveRAGDocument(document, embedding: embedding)

                        totalIndexed += 1

                        if totalIndexed % 10 == 0 {
                            print("  📊 Indexed \(totalIndexed) messages...")
                        }

                        // Rate limiting: small delay between API calls
                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

                    } catch {
                        print("  ⚠️ Failed to index message: \(error)")
                    }
                }
            }

            print("✅ Batch indexing complete: \(totalIndexed) messages indexed")

        } catch {
            print("❌ Batch indexing failed: \(error)")
        }
    }

    // MARK: - Semantic Search

    /// Search conversations by semantic similarity
    func semanticSearch(query: String, limit: Int = 10) async throws -> [ChatMessage] {
        guard let vectorSearch = vectorSearchService else {
            throw RAGError.servicesNotInitialized
        }

        let results = try await vectorSearch.hybridSearch(query: query, topK: limit)

        // Convert RAG documents back to ChatMessage format
        var chatMessages: [ChatMessage] = []

        for doc in results {
            let message = ChatMessage(
                id: doc.sourceId,
                content: doc.chunkText,
                isUser: false, // We don't track this in RAG docs
                timestamp: Date(), // Placeholder
                libraryId: doc.metadata["library_id"]
            )
            chatMessages.append(message)
        }

        return chatMessages
    }
}

// MARK: - RAG Error Types

enum RAGError: Error, LocalizedError {
    case servicesNotInitialized
    case embeddingFailed(String)
    case searchFailed(String)

    var errorDescription: String? {
        switch self {
        case .servicesNotInitialized:
            return "RAG services not initialized. Configure API key first."
        case .embeddingFailed(let message):
            return "Embedding generation failed: \(message)"
        case .searchFailed(let message):
            return "Semantic search failed: \(message)"
        }
    }
}

// MARK: - Add Properties to ChatViewModel

// Note: These properties should be added to the main ChatViewModel class:
/*

 Add these to ChatViewModel:

 // RAG Services
 private var embeddingService: EmbeddingService?
 private var vectorSearchService: VectorSearchService?
 private var ragContextBuilder: RAGContextBuilder?

 @Published var ragEnabled: Bool = false

 */
