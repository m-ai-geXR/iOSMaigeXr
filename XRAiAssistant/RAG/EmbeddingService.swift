//
//  EmbeddingService.swift
//  XRAiAssistant
//
//  Together AI embedding service for RAG system
//  Generates vector embeddings for semantic search
//

import Foundation

class EmbeddingService {
    private let apiKey: String
    private let embeddingModel = "togethercomputer/m2-bert-80M-8k-retrieval"
    private let embeddingDimension = 768

    init(apiKey: String) {
        self.apiKey = apiKey
        print("🧠 EmbeddingService initialized with model: \(embeddingModel)")
    }

    // MARK: - Single Embedding Generation

    /// Generate embedding for a single text
    func generateEmbedding(text: String) async throws -> [Float] {
        guard !text.isEmpty else {
            throw EmbeddingError.emptyText
        }

        print("🧠 Generating embedding for text (\(text.count) chars)...")

        let url = URL(string: "https://api.together.xyz/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": embeddingModel,
            "input": text
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw EmbeddingError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        // Parse response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataArray = json?["data"] as? [[String: Any]],
              let firstData = dataArray.first,
              let embedding = firstData["embedding"] as? [Double] else {
            throw EmbeddingError.invalidResponse
        }

        print("✅ Generated \(embedding.count)-dimensional embedding")
        return embedding.map { Float($0) }
    }

    // MARK: - Batch Embedding Generation

    /// Generate embeddings for multiple texts in batch (more efficient)
    func batchGenerateEmbeddings(texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }

        print("🧠 Generating batch embeddings for \(texts.count) texts...")

        let url = URL(string: "https://api.together.xyz/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": embeddingModel,
            "input": texts
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Batch embedding failed: \(errorText)")
            throw EmbeddingError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataArray = json?["data"] as? [[String: Any]] else {
            throw EmbeddingError.invalidResponse
        }

        var embeddings: [[Float]] = []
        for item in dataArray {
            if let embedding = item["embedding"] as? [Double] {
                embeddings.append(embedding.map { Float($0) })
            }
        }

        print("✅ Generated \(embeddings.count) embeddings")
        return embeddings
    }

    // MARK: - Batch Processing with Chunks

    /// Process large number of texts in smaller batches to avoid API limits
    func batchGenerateEmbeddingsChunked(texts: [String], batchSize: Int = 20) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }

        print("🧠 Generating embeddings for \(texts.count) texts in batches of \(batchSize)...")

        var allEmbeddings: [[Float]] = []

        for i in stride(from: 0, to: texts.count, by: batchSize) {
            let endIndex = min(i + batchSize, texts.count)
            let batch = Array(texts[i..<endIndex])

            print("  📦 Processing batch \(i/batchSize + 1)/\((texts.count + batchSize - 1) / batchSize)...")

            let batchEmbeddings = try await batchGenerateEmbeddings(texts: batch)
            allEmbeddings.append(contentsOf: batchEmbeddings)

            // Add small delay to respect rate limits
            if endIndex < texts.count {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }

        print("✅ Generated \(allEmbeddings.count) total embeddings")
        return allEmbeddings
    }
}

// MARK: - Errors

enum EmbeddingError: Error, LocalizedError {
    case emptyText
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Cannot generate embedding for empty text"
        case .invalidResponse:
            return "Invalid response from embedding API"
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        }
    }
}
