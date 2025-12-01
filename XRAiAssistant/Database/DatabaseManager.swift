//
//  DatabaseManager.swift
//  XRAiAssistant
//
//  SQLite database manager using GRDB.swift
//  Handles all database operations, migrations, and queries
//

import Foundation
import GRDB

@MainActor
class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue!
    private let databaseFileName = "XRAiAssistant.sqlite"

    private init() {
        setupDatabase()
    }

    // MARK: - Setup

    private func setupDatabase() {
        do {
            let fileManager = FileManager.default
            let dbPath = try fileManager
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent(databaseFileName)
                .path

            print("📁 Database path: \(dbPath)")

            dbQueue = try DatabaseQueue(path: dbPath)
            try migrator.migrate(dbQueue)

            print("✅ Database initialized successfully")
        } catch {
            fatalError("❌ Database initialization failed: \(error)")
        }
    }

    // MARK: - Migration System

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // v1: Initial schema
        migrator.registerMigration("v1_initial_schema") { db in
            print("🔄 Running migration: v1_initial_schema")

            // Settings table
            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
                t.column("type", .text).notNull()
                t.column("updated_at", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
            }

            // API Keys table (references to Keychain)
            try db.create(table: "api_keys") { t in
                t.column("provider", .text).primaryKey()
                t.column("keychain_key", .text).notNull()
                t.column("created_at", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updated_at", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
            }

            // Conversations table
            try db.create(table: "conversations") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("library_3d_id", .text)
                t.column("model_used", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("is_archived", .boolean).defaults(to: false)
                t.column("metadata", .text)
            }
            try db.create(index: "idx_conversations_updated", on: "conversations", columns: ["updated_at"])
            try db.create(index: "idx_conversations_library", on: "conversations", columns: ["library_3d_id"])

            // Messages table
            try db.create(table: "messages") { t in
                t.column("id", .text).primaryKey()
                t.column("conversation_id", .text).notNull()
                    .references("conversations", onDelete: .cascade)
                t.column("content", .text).notNull()
                t.column("is_user", .boolean).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("thread_parent_id", .text)
                t.column("library_id", .text)
                t.column("metadata", .text)
            }
            try db.create(index: "idx_messages_conversation", on: "messages", columns: ["conversation_id", "timestamp"])
            try db.create(index: "idx_messages_thread", on: "messages", columns: ["thread_parent_id"])

            // Messages FTS5 (Full-Text Search)
            try db.create(virtualTable: "messages_fts", using: FTS5()) { t in
                t.column("id")
                t.column("conversation_id")
                t.column("content")
                t.tokenizer = .porter()
            }

            // Attachments table
            try db.create(table: "message_attachments") { t in
                t.column("id", .text).primaryKey()
                t.column("message_id", .text).notNull()
                    .references("messages", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("mime_type", .text)
                t.column("data", .blob)
                t.column("file_path", .text)
                t.column("metadata", .text)
                t.column("created_at", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
            }
            try db.create(index: "idx_attachments_message", on: "message_attachments", columns: ["message_id"])

            print("✅ Migration v1_initial_schema completed")
        }

        // v2: RAG tables (will be activated in Phase 3)
        migrator.registerMigration("v2_rag_tables") { db in
            print("🔄 Running migration: v2_rag_tables")

            // RAG documents table
            try db.create(table: "rag_documents") { t in
                t.column("id", .text).primaryKey()
                t.column("source_type", .text).notNull()
                t.column("source_id", .text).notNull()
                t.column("chunk_text", .text).notNull()
                t.column("chunk_index", .integer).notNull()
                t.column("created_at", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
                t.column("metadata", .text)
            }
            try db.create(index: "idx_rag_documents_source", on: "rag_documents", columns: ["source_type", "source_id"])

            // RAG embeddings table
            try db.create(table: "rag_embeddings") { t in
                t.column("id", .text).primaryKey()
                t.column("document_id", .text).notNull()
                    .references("rag_documents", onDelete: .cascade)
                t.column("embedding", .blob).notNull()
                t.column("embedding_model", .text).notNull()
                t.column("dimension", .integer).notNull()
                t.column("created_at", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
            }
            try db.create(index: "idx_embeddings_document", on: "rag_embeddings", columns: ["document_id"])

            // RAG documents FTS5
            try db.create(virtualTable: "rag_documents_fts", using: FTS5()) { t in
                t.column("id")
                t.column("chunk_text")
                t.tokenizer = .porter()
            }

            print("✅ Migration v2_rag_tables completed")
        }

        return migrator
    }

    // MARK: - Settings CRUD

    func saveSetting(key: String, value: Any) async throws {
        try await dbQueue.write { db in
            let type: String
            let stringValue: String

            switch value {
            case let bool as Bool:
                type = "boolean"
                stringValue = bool ? "true" : "false"
            case let number as Double:
                type = "number"
                stringValue = "\(number)"
            case let number as Float:
                type = "number"
                stringValue = "\(number)"
            case let number as Int:
                type = "number"
                stringValue = "\(number)"
            case let string as String:
                type = "string"
                stringValue = string
            default:
                type = "json"
                let jsonData = try JSONSerialization.data(withJSONObject: value)
                stringValue = String(data: jsonData, encoding: .utf8) ?? ""
            }

            try db.execute(
                sql: """
                INSERT INTO settings (key, value, type, updated_at)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(key) DO UPDATE SET
                    value = excluded.value,
                    type = excluded.type,
                    updated_at = CURRENT_TIMESTAMP
                """,
                arguments: [key, stringValue, type]
            )
        }
    }

    func loadSetting(key: String) async throws -> Any? {
        try await dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT value, type FROM settings WHERE key = ?", arguments: [key]) else {
                return nil
            }

            let value: String = row["value"]
            let type: String = row["type"]

            switch type {
            case "boolean":
                return value == "true"
            case "number":
                return Double(value)
            case "string":
                return value
            case "json":
                guard let data = value.data(using: .utf8) else { return nil }
                return try JSONSerialization.jsonObject(with: data)
            default:
                return value
            }
        }
    }

    func loadAllSettings() async throws -> [String: Any] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT key, value, type FROM settings")
            var settings: [String: Any] = [:]

            for row in rows {
                let key: String = row["key"]
                let value: String = row["value"]
                let type: String = row["type"]

                switch type {
                case "boolean":
                    settings[key] = value == "true"
                case "number":
                    settings[key] = Double(value)
                case "string":
                    settings[key] = value
                case "json":
                    if let data = value.data(using: .utf8),
                       let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                        settings[key] = jsonObject
                    }
                default:
                    settings[key] = value
                }
            }

            return settings
        }
    }

    // MARK: - Conversation CRUD

    func saveConversation(_ conversation: Conversation) async throws {
        try await dbQueue.write { db in
            let metadataJSON = try? JSONEncoder().encode(["custom": "data"])

            try db.execute(
                sql: """
                INSERT INTO conversations (id, title, library_3d_id, model_used, created_at, updated_at, is_archived, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    library_3d_id = excluded.library_3d_id,
                    model_used = excluded.model_used,
                    updated_at = excluded.updated_at,
                    is_archived = excluded.is_archived,
                    metadata = excluded.metadata
                """,
                arguments: [
                    conversation.id.uuidString,
                    conversation.title,
                    conversation.library3DID,
                    conversation.modelUsed,
                    conversation.createdAt,
                    conversation.updatedAt,
                    false,
                    metadataJSON != nil ? String(data: metadataJSON!, encoding: .utf8) : nil
                ]
            )

            // Save messages
            for message in conversation.messages {
                try saveMessage(message, conversationId: conversation.id, db: db)
            }
        }
    }

    nonisolated private func saveMessage(_ message: EnhancedChatMessage, conversationId: UUID, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO messages (id, conversation_id, content, is_user, timestamp, thread_parent_id, library_id, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                content = excluded.content,
                metadata = excluded.metadata
            """,
            arguments: [
                message.id.uuidString,
                conversationId.uuidString,
                message.content,
                message.isUser,
                message.timestamp,
                message.threadParentID?.uuidString,
                message.libraryId,
                nil // metadata JSON
            ]
        )

        // Insert into FTS5
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO messages_fts (id, conversation_id, content)
            VALUES (?, ?, ?)
            """,
            arguments: [message.id.uuidString, conversationId.uuidString, message.content]
        )
    }

    func loadConversations(limit: Int = 100, offset: Int = 0) async throws -> [Conversation] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM conversations
                WHERE is_archived = 0
                ORDER BY updated_at DESC
                LIMIT ? OFFSET ?
                """, arguments: [limit, offset])

            var conversations: [Conversation] = []

            for row in rows {
                let conversationId = UUID(uuidString: row["id"])!
                let title: String = row["title"]
                let createdAt: Date = row["created_at"]
                let updatedAt: Date = row["updated_at"]
                let library3DID: String? = row["library_3d_id"]
                let modelUsed: String? = row["model_used"]

                // Load messages for this conversation
                let messages = try loadMessages(for: conversationId, db: db)

                let conversation = Conversation(
                    id: conversationId,
                    title: title,
                    messages: messages,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    library3DID: library3DID,
                    modelUsed: modelUsed
                )

                conversations.append(conversation)
            }

            return conversations
        }
    }

    nonisolated private func loadMessages(for conversationId: UUID, db: Database) throws -> [EnhancedChatMessage] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT * FROM messages
            WHERE conversation_id = ?
            ORDER BY timestamp ASC
            """, arguments: [conversationId.uuidString])

        return rows.map { row in
            EnhancedChatMessage(
                id: UUID(uuidString: row["id"])!,
                content: row["content"],
                isUser: row["is_user"],
                timestamp: row["timestamp"],
                threadParentID: (row["thread_parent_id"] as String?).flatMap { UUID(uuidString: $0) },
                replies: [],
                libraryId: row["library_id"]
            )
        }
    }

    func deleteConversation(_ id: UUID) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM conversations WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - Search

    func fullTextSearch(query: String, limit: Int = 50) async throws -> [EnhancedChatMessage] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT m.* FROM messages m
                JOIN messages_fts fts ON m.id = fts.id
                WHERE messages_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """, arguments: [query, limit])

            return rows.map { row in
                EnhancedChatMessage(
                    id: UUID(uuidString: row["id"])!,
                    content: row["content"],
                    isUser: row["is_user"],
                    timestamp: row["timestamp"],
                    threadParentID: (row["thread_parent_id"] as String?).flatMap { UUID(uuidString: $0) },
                    replies: [],
                    libraryId: row["library_id"]
                )
            }
        }
    }

    // MARK: - Background Indexing Support (for Phase 4)

    func loadUnindexedConversations() async throws -> [Conversation] {
        try await dbQueue.read { db in
            // Find conversations that don't have RAG embeddings
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.* FROM conversations c
                WHERE NOT EXISTS (
                    SELECT 1 FROM rag_documents r
                    WHERE r.source_id = c.id
                    AND r.source_type = 'conversation'
                )
                ORDER BY c.updated_at DESC
                LIMIT 10
                """)

            var conversations: [Conversation] = []

            for row in rows {
                let conversationId = UUID(uuidString: row["id"])!
                let messages = try loadMessages(for: conversationId, db: db)

                let conversation = Conversation(
                    id: conversationId,
                    title: row["title"],
                    messages: messages,
                    createdAt: row["created_at"],
                    updatedAt: row["updated_at"],
                    library3DID: row["library_3d_id"],
                    modelUsed: row["model_used"]
                )

                conversations.append(conversation)
            }

            return conversations
        }
    }

    // MARK: - RAG CRUD (Phase 3)

    func saveRAGDocument(_ document: RAGDocument, embedding: [Float]) async throws {
        try await dbQueue.write { db in
            // Encode metadata to JSON
            let metadataData = try JSONEncoder().encode(document.metadata)
            let metadataString = String(data: metadataData, encoding: .utf8)

            // Save document
            try db.execute(
                sql: """
                INSERT INTO rag_documents (id, source_type, source_id, chunk_text, chunk_index, metadata)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    chunk_text = excluded.chunk_text,
                    metadata = excluded.metadata
                """,
                arguments: [
                    document.id,
                    document.sourceType,
                    document.sourceId,
                    document.chunkText,
                    document.chunkIndex,
                    metadataString
                ]
            )

            // Save embedding
            let embeddingData = Data(bytes: embedding, count: embedding.count * MemoryLayout<Float>.size)
            let embeddingId = UUID().uuidString

            try db.execute(
                sql: """
                INSERT INTO rag_embeddings (id, document_id, embedding, embedding_model, dimension)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    embedding = excluded.embedding
                """,
                arguments: [
                    embeddingId,
                    document.id,
                    embeddingData,
                    "togethercomputer/m2-bert-80M-8k-retrieval",
                    embedding.count
                ]
            )

            // Insert into FTS5
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO rag_documents_fts (id, chunk_text)
                VALUES (?, ?)
                """,
                arguments: [document.id, document.chunkText]
            )
        }
    }

    func loadAllEmbeddings(sourceType: String? = nil) async throws -> [EmbeddingData] {
        try await dbQueue.read { db in
            var sql = """
                SELECT d.*, e.embedding FROM rag_documents d
                JOIN rag_embeddings e ON d.id = e.document_id
                """
            var arguments: [Any] = []

            if let sourceType = sourceType {
                sql += " WHERE d.source_type = ?"
                arguments.append(sourceType)
            }

            let rows: [Row]
            if arguments.isEmpty {
                rows = try Row.fetchAll(db, sql: sql)
            } else {
                rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)!)
            }

            return rows.compactMap { row -> EmbeddingData? in
                guard let embeddingData = row["embedding"] as? Data else { return nil }

                let embedding = embeddingData.withUnsafeBytes { ptr in
                    Array(ptr.bindMemory(to: Float.self))
                }

                let metadataStr: String? = row["metadata"]
                var metadata: [String: String] = [:]
                if let metadataStr = metadataStr,
                   let data = metadataStr.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                    metadata = decoded
                }

                let document = RAGDocument(
                    id: row["id"],
                    sourceType: row["source_type"],
                    sourceId: row["source_id"],
                    chunkText: row["chunk_text"],
                    chunkIndex: row["chunk_index"],
                    metadata: metadata
                )

                return EmbeddingData(document: document, embedding: embedding)
            }
        }
    }

    func loadEmbedding(documentId: String) async throws -> [Float]? {
        try await dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT embedding FROM rag_embeddings WHERE document_id = ?
                """, arguments: [documentId]) else {
                return nil
            }

            guard let embeddingData = row["embedding"] as? Data else { return nil }

            return embeddingData.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self))
            }
        }
    }

    func fullTextSearchRAG(query: String, limit: Int = 50, sourceType: String? = nil) async throws -> [RAGDocument] {
        try await dbQueue.read { db in
            var sql = """
                SELECT d.* FROM rag_documents d
                JOIN rag_documents_fts fts ON d.id = fts.id
                WHERE rag_documents_fts MATCH ?
                """
            var arguments: [Any] = [query]

            if let sourceType = sourceType {
                sql += " AND d.source_type = ?"
                arguments.append(sourceType)
            }

            sql += " ORDER BY rank LIMIT ?"
            arguments.append(limit)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)!)

            return rows.map { row in
                let metadataStr: String? = row["metadata"]
                var metadata: [String: String] = [:]
                if let metadataStr = metadataStr,
                   let data = metadataStr.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                    metadata = decoded
                }

                return RAGDocument(
                    id: row["id"],
                    sourceType: row["source_type"],
                    sourceId: row["source_id"],
                    chunkText: row["chunk_text"],
                    chunkIndex: row["chunk_index"],
                    metadata: metadata
                )
            }
        }
    }

    func loadEmbeddingsForConversation(conversationId: UUID) async throws -> [[Float]] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT e.embedding FROM rag_embeddings e
                JOIN rag_documents d ON e.document_id = d.id
                WHERE d.source_id = ? AND d.source_type = 'conversation'
                """, arguments: [conversationId.uuidString])

            return rows.compactMap { row -> [Float]? in
                guard let embeddingData = row["embedding"] as? Data else { return nil }
                return embeddingData.withUnsafeBytes { ptr in
                    Array(ptr.bindMemory(to: Float.self))
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct RAGDocument {
    let id: String
    let sourceType: String
    let sourceId: String
    let chunkText: String
    let chunkIndex: Int
    let metadata: [String: String]
    var relevanceScore: Float = 0.0
}

struct EmbeddingData {
    let document: RAGDocument
    let embedding: [Float]
}
