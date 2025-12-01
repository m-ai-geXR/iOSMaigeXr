//
//  VectorSearchService.swift
//  XRAiAssistant
//
//  Vector-based semantic search using cosine similarity
//  Supports both pure semantic search and hybrid FTS5+vector search
//

import Foundation

@MainActor
class VectorSearchService {
    private let db = DatabaseManager.shared
    private let embeddingService: EmbeddingService

    init(embeddingService: EmbeddingService) {
        self.embeddingService = embeddingService
        print("🔍 VectorSearchService initialized")
    }

    // MARK: - Similarity Calculation

    /// Calculate cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0, magnitudeB > 0 else { return 0.0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    // MARK: - Semantic Search

    /// Pure vector-based semantic search
    func semanticSearch(query: String, topK: Int = 5, sourceType: String? = nil) async throws -> [RAGDocument] {
        print("🔍 Semantic search for: \(query.prefix(50))...")

        // 1. Generate query embedding
        let queryEmbedding = try await embeddingService.generateEmbedding(text: query)

        // 2. Load all embeddings from database
        let allEmbeddings = try await db.loadAllEmbeddings(sourceType: sourceType)

        print("  📊 Comparing against \(allEmbeddings.count) embeddings...")

        // 3. Calculate similarities
        var results: [(document: RAGDocument, score: Float)] = []
        for embeddingData in allEmbeddings {
            let score = cosineSimilarity(queryEmbedding, embeddingData.embedding)
            var doc = embeddingData.document
            doc.relevanceScore = score
            results.append((document: doc, score: score))
        }

        // 4. Sort by similarity and return top-K
        let topResults = results
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0.document }

        print("  ✅ Found \(topResults.count) relevant documents (top score: \(String(format: "%.3f", topResults.first?.relevanceScore ?? 0)))")
        return topResults
    }

    // MARK: - Hybrid Search

    /// Hybrid search: FTS5 keyword + vector semantic (best results)
    func hybridSearch(query: String, topK: Int = 10, sourceType: String? = nil) async throws -> [RAGDocument] {
        print("🔍 Hybrid search for: \(query.prefix(50))...")

        // 1. FTS5 keyword search (fast pre-filter)
        let keywordResults = try await db.fullTextSearchRAG(query: query, limit: 50, sourceType: sourceType)

        guard !keywordResults.isEmpty else {
            print("  ℹ️ No keyword matches, falling back to pure semantic search")
            return try await semanticSearch(query: query, topK: topK, sourceType: sourceType)
        }

        print("  📊 FTS5 found \(keywordResults.count) keyword matches")

        // 2. Generate query embedding
        let queryEmbedding = try await embeddingService.generateEmbedding(text: query)

        // 3. Score keyword results with semantic similarity
        var scored: [(doc: RAGDocument, score: Float)] = []
        for (index, doc) in keywordResults.enumerated() {
            guard let embedding = try await db.loadEmbedding(documentId: doc.id) else {
                continue
            }

            let semanticScore = cosineSimilarity(queryEmbedding, embedding)

            // FTS5 rank (higher index = lower rank)
            let keywordScore = Float(keywordResults.count - index) / Float(keywordResults.count)

            // Combine scores: 60% semantic + 40% keyword
            let finalScore = 0.6 * semanticScore + 0.4 * keywordScore

            var scoredDoc = doc
            scoredDoc.relevanceScore = finalScore
            scored.append((doc: scoredDoc, score: finalScore))
        }

        // 4. Return top-K by combined score
        let topResults = scored
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0.doc }

        print("  ✅ Hybrid search returned \(topResults.count) documents (top score: \(String(format: "%.3f", topResults.first?.relevanceScore ?? 0)))")
        return topResults
    }

    // MARK: - Conversation Similarity

    /// Find conversations similar to a given conversation
    func findSimilarConversations(conversationId: UUID, topK: Int = 5) async throws -> [Conversation] {
        print("🔍 Finding conversations similar to: \(conversationId.uuidString.prefix(8))...")

        // 1. Get embeddings for the conversation
        let embeddings = try await db.loadEmbeddingsForConversation(conversationId: conversationId)

        guard !embeddings.isEmpty else {
            print("  ⚠️ No embeddings found for conversation")
            return []
        }

        // 2. Calculate average embedding for the conversation
        let avgEmbedding = averageEmbedding(embeddings)

        // 3. Load all other conversations' embeddings
        let allEmbeddings = try await db.loadAllEmbeddings(sourceType: "conversation")

        // 4. Group by conversation and calculate similarity
        var conversationScores: [String: (embedding: [Float], count: Int)] = [:]

        for embeddingData in allEmbeddings where embeddingData.document.sourceId != conversationId.uuidString {
            let sourceId = embeddingData.document.sourceId

            if var existing = conversationScores[sourceId] {
                // Accumulate embeddings for averaging
                for i in 0..<embeddingData.embedding.count {
                    existing.embedding[i] += embeddingData.embedding[i]
                }
                existing.count += 1
                conversationScores[sourceId] = existing
            } else {
                conversationScores[sourceId] = (embedding: embeddingData.embedding, count: 1)
            }
        }

        // 5. Calculate average embeddings and similarities
        var similarities: [(conversationId: UUID, score: Float)] = []

        for (sourceId, data) in conversationScores {
            let avgOtherEmbedding = data.embedding.map { $0 / Float(data.count) }
            let similarity = cosineSimilarity(avgEmbedding, avgOtherEmbedding)

            if let uuid = UUID(uuidString: sourceId) {
                similarities.append((conversationId: uuid, score: similarity))
            }
        }

        // 6. Sort and get top-K
        let topSimilar = similarities
            .sorted { $0.score > $1.score }
            .prefix(topK)

        // 7. Load full conversations
        let conversations = try await db.loadConversations(limit: 1000)
        let similarConversations = topSimilar.compactMap { item in
            conversations.first { $0.id == item.conversationId }
        }

        print("  ✅ Found \(similarConversations.count) similar conversations")
        return similarConversations
    }

    // MARK: - Helpers

    private func averageEmbedding(_ embeddings: [[Float]]) -> [Float] {
        guard !embeddings.isEmpty else { return [] }

        let dimension = embeddings[0].count
        var avg = [Float](repeating: 0, count: dimension)

        for embedding in embeddings {
            for (i, value) in embedding.enumerated() {
                avg[i] += value
            }
        }

        return avg.map { $0 / Float(embeddings.count) }
    }
}
