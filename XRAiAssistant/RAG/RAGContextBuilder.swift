//
//  RAGContextBuilder.swift
//  XRAiAssistant
//
//  Assembles context from RAG search results for AI prompts
//  Token-aware context building with relevance scoring
//

import Foundation

class RAGContextBuilder {
    private let vectorSearch: VectorSearchService
    private let maxContextTokens = 3000 // Reserve ~1000 tokens for user query + AI response

    init(vectorSearch: VectorSearchService) {
        self.vectorSearch = vectorSearch
        print("🔨 RAGContextBuilder initialized")
    }

    // MARK: - Context Building

    /// Build RAG context from conversation history for a user query
    func buildContext(for userQuery: String, libraryId: String? = nil, topK: Int = 10) async throws -> String {
        print("🔨 Building RAG context for query: \(userQuery.prefix(50))...")

        // 1. Hybrid search for relevant chunks (keyword + semantic)
        var relevantDocs = try await vectorSearch.hybridSearch(query: userQuery, topK: topK * 2) // Get extra for filtering

        // 2. Filter by library if specified
        if let libraryId = libraryId {
            relevantDocs = relevantDocs.filter { doc in
                doc.metadata["library_id"] == libraryId
            }
            print("  📚 Filtered to library: \(libraryId) (\(relevantDocs.count) docs)")
        }

        // 3. Take top-K after filtering
        relevantDocs = Array(relevantDocs.prefix(topK))

        guard !relevantDocs.isEmpty else {
            print("  ℹ️ No relevant context found")
            return ""
        }

        // 4. Build context string (token-aware)
        var context = "# Relevant Context from Previous Conversations:\n\n"
        var tokenCount = 0
        var chunksIncluded = 0

        for doc in relevantDocs {
            let relevancePercent = Int(doc.relevanceScore * 100)
            let chunk = """
            ---
            **Relevance**: \(relevancePercent)% | **Source**: \(doc.sourceType)
            \(doc.chunkText)


            """

            let chunkTokens = estimateTokens(chunk)

            // Check if adding this chunk exceeds token limit
            if tokenCount + chunkTokens > maxContextTokens {
                print("  ⚠️ Reached token limit (\(maxContextTokens)), stopping at \(chunksIncluded) chunks")
                break
            }

            context += chunk
            tokenCount += chunkTokens
            chunksIncluded += 1
        }

        if chunksIncluded == 0 {
            print("  ℹ️ No chunks fit within token limit")
            return ""
        }

        print("  ✅ Built context with \(chunksIncluded) chunks (~\(tokenCount) tokens)")
        return context
    }

    // MARK: - Conversation-Specific Context

    /// Build context for continuing a specific conversation
    func buildConversationContext(conversationId: UUID, userQuery: String) async throws -> String {
        print("🔨 Building conversation context for: \(conversationId.uuidString.prefix(8))...")

        // Search within the specific conversation
        let relevantDocs = try await vectorSearch.hybridSearch(
            query: userQuery,
            topK: 5,
            sourceType: "conversation"
        ).filter { $0.sourceId == conversationId.uuidString }

        guard !relevantDocs.isEmpty else {
            print("  ℹ️ No relevant context in this conversation")
            return ""
        }

        var context = "# Relevant Context from This Conversation:\n\n"
        var tokenCount = 0

        for doc in relevantDocs {
            let chunk = """
            \(doc.chunkText)

            """

            let chunkTokens = estimateTokens(chunk)

            if tokenCount + chunkTokens > maxContextTokens {
                break
            }

            context += chunk
            tokenCount += chunkTokens
        }

        print("  ✅ Built conversation context (~\(tokenCount) tokens)")
        return context
    }

    // MARK: - Code-Specific Context

    /// Build context focused on code examples and patterns
    func buildCodeContext(query: String, language: String? = nil) async throws -> String {
        print("🔨 Building code context for: \(query.prefix(50))...")

        // Search for code-related content
        var searchQuery = query
        if let language = language {
            searchQuery += " \(language) code example"
        }

        let relevantDocs = try await vectorSearch.hybridSearch(query: searchQuery, topK: 8)

        // Filter for docs that likely contain code (heuristic: contains common code patterns)
        let codeDocs = relevantDocs.filter { doc in
            let text = doc.chunkText.lowercased()
            return text.contains("function") ||
                   text.contains("const") ||
                   text.contains("class") ||
                   text.contains("import") ||
                   text.contains("```") ||
                   text.contains("{") ||
                   text.contains("=>")
        }

        guard !codeDocs.isEmpty else {
            print("  ℹ️ No code examples found")
            return ""
        }

        var context = "# Relevant Code Examples:\n\n"
        var tokenCount = 0

        for doc in codeDocs.prefix(5) {
            let chunk = """
            ```
            \(doc.chunkText)
            ```

            """

            let chunkTokens = estimateTokens(chunk)

            if tokenCount + chunkTokens > maxContextTokens {
                break
            }

            context += chunk
            tokenCount += chunkTokens
        }

        print("  ✅ Built code context with \(codeDocs.count) examples (~\(tokenCount) tokens)")
        return context
    }

    // MARK: - Multi-Turn Context (Advanced)

    /// Build context that considers multiple recent user messages
    func buildMultiTurnContext(recentMessages: [String], libraryId: String? = nil) async throws -> String {
        print("🔨 Building multi-turn context from \(recentMessages.count) messages...")

        // Combine recent messages into a compound query
        let compoundQuery = recentMessages.joined(separator: " ")

        // Perform search with compound query
        var relevantDocs = try await vectorSearch.hybridSearch(query: compoundQuery, topK: 15)

        // Filter by library if specified
        if let libraryId = libraryId {
            relevantDocs = relevantDocs.filter { $0.metadata["library_id"] == libraryId }
        }

        // Group by conversation to avoid redundancy
        var seenConversations = Set<String>()
        var uniqueDocs: [RAGDocument] = []

        for doc in relevantDocs {
            if !seenConversations.contains(doc.sourceId) {
                uniqueDocs.append(doc)
                seenConversations.insert(doc.sourceId)

                if uniqueDocs.count >= 8 {
                    break
                }
            }
        }

        var context = "# Relevant Context (Multi-Turn):\n\n"
        var tokenCount = 0

        for doc in uniqueDocs {
            let chunk = """
            ---
            \(doc.chunkText)

            """

            let chunkTokens = estimateTokens(chunk)

            if tokenCount + chunkTokens > maxContextTokens {
                break
            }

            context += chunk
            tokenCount += chunkTokens
        }

        print("  ✅ Built multi-turn context with \(uniqueDocs.count) unique conversations (~\(tokenCount) tokens)")
        return context
    }

    // MARK: - Helpers

    /// Rough token estimation (4 chars ≈ 1 token)
    private func estimateTokens(_ text: String) -> Int {
        return text.count / 4
    }

    /// Truncate context to fit within token limit
    func truncateContext(_ context: String, maxTokens: Int) -> String {
        let estimatedTokens = estimateTokens(context)

        if estimatedTokens <= maxTokens {
            return context
        }

        // Truncate by character count (rough approximation)
        let maxChars = maxTokens * 4
        if context.count > maxChars {
            let truncated = String(context.prefix(maxChars))
            return truncated + "\n\n...(context truncated)"
        }

        return context
    }
}
