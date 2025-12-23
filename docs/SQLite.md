# SQLite Migration & RAG Implementation Plan

> **XRAiAssistant iOS** - Migrating from UserDefaults to SQLite with RAG capabilities

## Table of Contents

- [Overview](#overview)
- [Current State Analysis](#current-state-analysis)
- [Architecture](#architecture)
- [Phase 1: SQLite Foundation](#phase-1-sqlite-foundation)
- [Phase 2: Data Migration](#phase-2-data-migration)
- [Phase 3: RAG System](#phase-3-rag-system)
- [Phase 4: Background Indexing](#phase-4-background-indexing)
- [Phase 5: Advanced Features](#phase-5-advanced-features)
- [Implementation Checklist](#implementation-checklist)
- [Technical Decisions](#technical-decisions)
- [Performance](#performance)
- [Security](#security)
- [Testing](#testing)

---

## Overview

This document outlines the complete plan for migrating XRAiAssistant from UserDefaults-based storage to SQLite, with full RAG (Retrieval-Augmented Generation) capabilities for semantic search and context-aware AI responses.

### Goals

1. ✅ Migrate all user state from UserDefaults to SQLite
2. ✅ Implement vector embeddings for semantic search
3. ✅ Build RAG system for context-aware AI responses
4. ✅ Enable full-text search on conversation history
5. ✅ Support multimodal content (images, code, files)
6. ✅ Maintain backwards compatibility during migration

### Timeline

**Total Duration**: 5-6 weeks
- Phase 1: SQLite Foundation (Weeks 1-2)
- Phase 2: Data Migration (Week 2)
- Phase 3: RAG System (Weeks 3-4)
- Phase 4: Background Indexing (Weeks 4-5)
- Phase 5: Advanced Features (Weeks 5-6)

---

## Current State Analysis

### User State Storage (UserDefaults)

**Settings**:
- API keys for multiple providers (Together.ai, Google AI, Anthropic, OpenAI, CodeSandbox)
- AI parameters: `temperature`, `topP`, `selectedModel`, `systemPrompt`
- Library3D settings (selected framework)
- All stored with `XRAiAssistant_` prefix

**Conversation History**:
- Stored via `ConversationStorageManager`
- JSON serialization to UserDefaults
- Key: `XRAiAssistant_Conversations`
- Max 100 conversations (hardcoded limit)

**Files**:
- [ChatViewModel.swift](XRAiAssistant/ChatViewModel.swift#L1381-L1450) - Settings persistence
- [ConversationModels.swift](XRAiAssistant/Models/ConversationModels.swift) - Data models
- [AIProviderManager.swift](XRAiAssistant/AIProviders/AIProviderManager.swift) - API key management

### Limitations

❌ **UserDefaults Issues**:
- ~1MB practical size limit
- No querying or indexing
- No relationships between data
- JSON serialization overhead
- No full-text search

❌ **Missing Capabilities**:
- Semantic search on conversations
- Context retrieval for AI (RAG)
- Advanced filtering/sorting
- Multimodal content optimization
- Conversation analytics

---

## Architecture

### Technology Stack

**Database**: SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift)
- Type-safe Swift API
- Full-text search (FTS5)
- Migration system
- Async/await support
- Reactive observations

**Embeddings**: Together AI
- Model: `togethercomputer/m2-bert-80M-8k-retrieval`
- Dimensions: 768
- Context length: 8K tokens
- Alternative: `WhereIsAI/UAE-Large-V1` (1024 dims)

**Search Strategy**: Hybrid
- FTS5 for keyword search (fast pre-filter)
- Vector search for semantic similarity
- Combined scoring (60% semantic + 40% keyword)

### Directory Structure

```
XRAiAssistant/
├── Database/
│   ├── DatabaseManager.swift          # Core database operations
│   ├── Schema.swift                    # Table definitions
│   ├── Models/
│   │   ├── DBConversation.swift       # Database models
│   │   ├── DBMessage.swift
│   │   ├── DBSettings.swift
│   │   └── DBRAGDocument.swift
│   └── Migration/
│       └── UserDefaultsMigrator.swift # Migration from UserDefaults
├── RAG/
│   ├── EmbeddingService.swift         # Vector embedding generation
│   ├── VectorSearchService.swift      # Semantic search
│   ├── RAGContextBuilder.swift        # Context assembly for AI
│   └── BackgroundIndexer.swift        # Background embedding generation
└── Services/
    └── DatabaseExporter.swift         # Backup/restore
```

---

## Phase 1: SQLite Foundation

**Duration**: Weeks 1-2
**Goal**: Set up SQLite database with complete schema and CRUD operations

### 1.1 Add GRDB Dependency

**File**: `XRAiAssistant.xcodeproj/project.pbxproj`

Add to Swift Package Manager:
```swift
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
]
```

### 1.2 Database Schema

**File**: `XRAiAssistant/Database/Schema.swift`

```sql
-- Settings Table
CREATE TABLE settings (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL,
    type TEXT NOT NULL,              -- 'string', 'number', 'boolean', 'json'
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- API Keys Table (keys stored in iOS Keychain, reference here)
CREATE TABLE api_keys (
    provider TEXT PRIMARY KEY NOT NULL,
    keychain_key TEXT NOT NULL,      -- Reference to Keychain item
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Conversations Table
CREATE TABLE conversations (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    library_3d_id TEXT,
    model_used TEXT,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    is_archived BOOLEAN DEFAULT 0,
    metadata TEXT                    -- JSON for flexible storage
);
CREATE INDEX idx_conversations_updated ON conversations(updated_at DESC);
CREATE INDEX idx_conversations_library ON conversations(library_3d_id);

-- Messages Table
CREATE TABLE messages (
    id TEXT PRIMARY KEY NOT NULL,
    conversation_id TEXT NOT NULL,
    content TEXT NOT NULL,
    is_user BOOLEAN NOT NULL,
    timestamp DATETIME NOT NULL,
    thread_parent_id TEXT,           -- For threaded replies
    library_id TEXT,
    metadata TEXT,                   -- JSON for images, code blocks, etc.
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);
CREATE INDEX idx_messages_conversation ON messages(conversation_id, timestamp);
CREATE INDEX idx_messages_thread ON messages(thread_parent_id);

-- Full-Text Search on Messages (FTS5)
CREATE VIRTUAL TABLE messages_fts USING fts5(
    id UNINDEXED,
    conversation_id UNINDEXED,
    content,
    tokenize = 'porter'              -- English stemming
);

-- Attachments Table (multimodal content)
CREATE TABLE message_attachments (
    id TEXT PRIMARY KEY NOT NULL,
    message_id TEXT NOT NULL,
    type TEXT NOT NULL,              -- 'image', 'code', 'file'
    mime_type TEXT,
    data BLOB,                       -- Compressed/optimized data
    file_path TEXT,                  -- For large files stored separately
    metadata TEXT,                   -- JSON
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);
CREATE INDEX idx_attachments_message ON message_attachments(message_id);

-- RAG Documents Table (chunked content for embeddings)
CREATE TABLE rag_documents (
    id TEXT PRIMARY KEY NOT NULL,
    source_type TEXT NOT NULL,       -- 'conversation', 'code', 'documentation'
    source_id TEXT NOT NULL,         -- conversation_id or message_id
    chunk_text TEXT NOT NULL,
    chunk_index INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    metadata TEXT                    -- JSON
);
CREATE INDEX idx_rag_documents_source ON rag_documents(source_type, source_id);

-- Vector Embeddings Table
CREATE TABLE rag_embeddings (
    id TEXT PRIMARY KEY NOT NULL,
    document_id TEXT NOT NULL,
    embedding BLOB NOT NULL,         -- Serialized float array (768 * 4 bytes)
    embedding_model TEXT NOT NULL,   -- 'togethercomputer/m2-bert-80M-8k-retrieval'
    dimension INTEGER NOT NULL,      -- 768
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (document_id) REFERENCES rag_documents(id) ON DELETE CASCADE
);
CREATE INDEX idx_embeddings_document ON rag_embeddings(document_id);

-- Full-Text Search on RAG Documents
CREATE VIRTUAL TABLE rag_documents_fts USING fts5(
    id UNINDEXED,
    chunk_text,
    tokenize = 'porter'
);
```

### 1.3 Database Manager

**File**: `XRAiAssistant/Database/DatabaseManager.swift`

```swift
import GRDB
import Foundation

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

            // API Keys table
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

            // Messages FTS5
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

        // v2: RAG tables (will be added in Phase 3)
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
            case let number as any Numeric:
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

    private func saveMessage(_ message: EnhancedChatMessage, conversationId: UUID, db: Database) throws {
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
            sql: "INSERT INTO messages_fts (id, conversation_id, content) VALUES (?, ?, ?)",
            arguments: [message.id.uuidString, conversationId.uuidString, message.content]
        )
    }

    func loadConversations(limit: Int = 100, offset: Int = 0) async throws -> [Conversation] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM conversations
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

    private func loadMessages(for conversationId: UUID, db: Database) throws -> [EnhancedChatMessage] {
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
}
```

### 1.4 Deliverables

- [ ] GRDB.swift added to project dependencies
- [ ] `Database/` directory created
- [ ] `DatabaseManager.swift` implemented with basic CRUD
- [ ] Migration system working (v1_initial_schema)
- [ ] Unit tests for database operations
- [ ] Build succeeds with no errors

---

## Phase 2: Data Migration

**Duration**: Week 2
**Goal**: Migrate all UserDefaults data to SQLite without data loss

### 2.1 User Defaults Migrator

**File**: `XRAiAssistant/Database/Migration/UserDefaultsMigrator.swift`

```swift
import Foundation

class UserDefaultsMigrator {
    private let db = DatabaseManager.shared
    private let migrationCompleteKey = "XRAiAssistant_SQLiteMigrationComplete"

    func shouldMigrate() -> Bool {
        return !UserDefaults.standard.bool(forKey: migrationCompleteKey)
    }

    func migrateToSQLite() async throws {
        print("🔄 Starting migration from UserDefaults to SQLite...")

        // 1. Migrate settings
        try await migrateSettings()

        // 2. Migrate API keys
        try await migrateAPIKeys()

        // 3. Migrate conversations
        try await migrateConversations()

        // 4. Mark migration complete
        UserDefaults.standard.set(true, forKey: migrationCompleteKey)
        print("✅ Migration complete!")
    }

    private func migrateSettings() async throws {
        print("📝 Migrating settings...")

        let keysToMigrate: [(key: String, type: String)] = [
            ("XRAiAssistant_SystemPrompt", "string"),
            ("XRAiAssistant_SelectedModel", "string"),
            ("XRAiAssistant_Temperature", "number"),
            ("XRAiAssistant_TopP", "number"),
            ("XRAiAssistant_APIKey", "string") // Legacy
        ]

        for (key, _) in keysToMigrate {
            if let value = UserDefaults.standard.object(forKey: key) {
                try await db.saveSetting(key: key, value: value)
                print("  ✅ Migrated: \(key)")
            }
        }
    }

    private func migrateAPIKeys() async throws {
        print("🔑 Migrating API keys...")

        let providers = ["Together.ai", "Google AI", "Anthropic", "OpenAI", "CodeSandbox"]

        for provider in providers {
            let key = "XRAiAssistant_APIKey_\(provider)"
            if let apiKey = UserDefaults.standard.string(forKey: key) {
                // TODO: Move to iOS Keychain in Phase 3
                try await db.saveSetting(key: key, value: apiKey)
                print("  ✅ Migrated API key for: \(provider)")
            }
        }
    }

    private func migrateConversations() async throws {
        print("💬 Migrating conversations...")

        guard let data = UserDefaults.standard.data(forKey: "XRAiAssistant_Conversations") else {
            print("  ℹ️ No conversations to migrate")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let conversations = try decoder.decode([Conversation].self, from: data)

        print("  📦 Found \(conversations.count) conversations to migrate")

        for (index, conversation) in conversations.enumerated() {
            try await db.saveConversation(conversation)
            print("  ✅ Migrated conversation \(index + 1)/\(conversations.count): \(conversation.title)")
        }
    }
}
```

### 2.2 Update App Initialization

**File**: `XRAiAssistant/XRAiAssistant.swift`

```swift
@main
struct XRAiAssistant: App {
    @StateObject private var chatViewModel = ChatViewModel()

    init() {
        // Run migration on first launch
        Task {
            let migrator = UserDefaultsMigrator()
            if migrator.shouldMigrate() {
                do {
                    try await migrator.migrateToSQLite()
                } catch {
                    print("❌ Migration failed: \(error)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chatViewModel)
        }
    }
}
```

### 2.3 Update ChatViewModel

**File**: `XRAiAssistant/ChatViewModel.swift`

Replace UserDefaults calls with DatabaseManager:

```swift
// BEFORE
func saveSettings() {
    UserDefaults.standard.set(apiKey, forKey: "XRAiAssistant_APIKey")
    UserDefaults.standard.set(systemPrompt, forKey: "XRAiAssistant_SystemPrompt")
    // ...
}

// AFTER
func saveSettings() async {
    do {
        try await DatabaseManager.shared.saveSetting(key: "XRAiAssistant_APIKey", value: apiKey)
        try await DatabaseManager.shared.saveSetting(key: "XRAiAssistant_SystemPrompt", value: systemPrompt)
        try await DatabaseManager.shared.saveSetting(key: "XRAiAssistant_Temperature", value: temperature)
        try await DatabaseManager.shared.saveSetting(key: "XRAiAssistant_TopP", value: topP)
        print("✅ Settings saved to SQLite")
    } catch {
        print("❌ Failed to save settings: \(error)")
    }
}

private func loadSettings() async {
    do {
        if let savedAPIKey = try await DatabaseManager.shared.loadSetting(key: "XRAiAssistant_APIKey") as? String {
            apiKey = savedAPIKey
        }
        if let savedPrompt = try await DatabaseManager.shared.loadSetting(key: "XRAiAssistant_SystemPrompt") as? String {
            systemPrompt = savedPrompt
        }
        if let temp = try await DatabaseManager.shared.loadSetting(key: "XRAiAssistant_Temperature") as? Double {
            temperature = temp
        }
        if let top = try await DatabaseManager.shared.loadSetting(key: "XRAiAssistant_TopP") as? Double {
            topP = top
        }
        print("✅ Settings loaded from SQLite")
    } catch {
        print("❌ Failed to load settings: \(error)")
    }
}
```

### 2.4 Update ConversationStorageManager

**File**: `XRAiAssistant/Models/ConversationModels.swift`

```swift
@MainActor
class ConversationStorageManager: ObservableObject {
    @Published var conversations: [Conversation] = []
    private let db = DatabaseManager.shared

    init() {
        Task {
            await loadConversations()
        }
    }

    func loadConversations() async {
        do {
            conversations = try await db.loadConversations()
            print("📂 Loaded \(conversations.count) conversations from SQLite")
        } catch {
            print("❌ Failed to load conversations: \(error)")
        }
    }

    func saveConversations() async {
        // Individual saves happen in addConversation/updateConversation
        print("💾 Conversations auto-saved to SQLite")
    }

    func addConversation(_ conversation: Conversation) async {
        var newConversation = conversation
        newConversation.generateTitleIfNeeded()
        conversations.insert(newConversation, at: 0)

        do {
            try await db.saveConversation(newConversation)
            print("✅ Conversation saved to SQLite")
        } catch {
            print("❌ Failed to save conversation: \(error)")
        }
    }
}
```

### 2.5 Deliverables

- [ ] `UserDefaultsMigrator.swift` implemented
- [ ] Migration runs on first app launch
- [ ] ChatViewModel updated to use SQLite
- [ ] ConversationStorageManager updated to use SQLite
- [ ] All user data successfully migrated
- [ ] Backwards compatibility maintained
- [ ] Build and test on device/simulator

---

## Phase 3: RAG System

**Duration**: Weeks 3-4
**Goal**: Implement vector embeddings and semantic search

### 3.1 Enable RAG Tables Migration

**Update**: `DatabaseManager.swift`

The `v2_rag_tables` migration is already defined in the migrator. It will run automatically when the app launches after this phase begins.

### 3.2 Embedding Service

**File**: `XRAiAssistant/RAG/EmbeddingService.swift`

```swift
import Foundation
import AIProxy

class EmbeddingService {
    private let apiKey: String
    private let embeddingModel = "togethercomputer/m2-bert-80M-8k-retrieval"
    private let embeddingDimension = 768

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // Generate embedding for single text
    func generateEmbedding(text: String) async throws -> [Float] {
        guard !text.isEmpty else {
            throw EmbeddingError.emptyText
        }

        print("🧠 Generating embedding for text (\(text.count) chars)...")

        // Together AI Embeddings API
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

    // Generate embeddings in batch
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
}

enum EmbeddingError: Error {
    case emptyText
    case invalidResponse
    case apiError(statusCode: Int, message: String)
}
```

### 3.3 Vector Search Service

**File**: `XRAiAssistant/RAG/VectorSearchService.swift`

```swift
import Foundation

struct RAGDocument {
    let id: String
    let sourceType: String
    let sourceId: String
    let chunkText: String
    let chunkIndex: Int
    let metadata: [String: Any]
    var relevanceScore: Float = 0.0
}

class VectorSearchService {
    private let db = DatabaseManager.shared
    private let embeddingService: EmbeddingService

    init(embeddingService: EmbeddingService) {
        self.embeddingService = embeddingService
    }

    // Cosine similarity calculation
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0.0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0, magnitudeB > 0 else { return 0.0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    // Semantic search using vector embeddings
    func semanticSearch(query: String, topK: Int = 5, sourceType: String? = nil) async throws -> [RAGDocument] {
        print("🔍 Semantic search for: \(query)")

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

        print("  ✅ Found \(topResults.count) relevant documents")
        return topResults
    }

    // Hybrid search: FTS5 keyword + vector semantic
    func hybridSearch(query: String, topK: Int = 10, sourceType: String? = nil) async throws -> [RAGDocument] {
        print("🔍 Hybrid search for: \(query)")

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
        for doc in keywordResults {
            guard let embedding = try await db.loadEmbedding(documentId: doc.id) else {
                continue
            }

            let semanticScore = cosineSimilarity(queryEmbedding, embedding)

            // Combine scores: 60% semantic + 40% keyword (from FTS5 rank)
            let keywordScore = 1.0 / Float(scored.count + 1) // Rough FTS5 rank proxy
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

        print("  ✅ Hybrid search returned \(topResults.count) documents")
        return topResults
    }
}
```

### 3.4 RAG Context Builder

**File**: `XRAiAssistant/RAG/RAGContextBuilder.swift`

```swift
import Foundation

class RAGContextBuilder {
    private let vectorSearch: VectorSearchService
    private let maxContextTokens = 3000 // Reserve tokens for user query + AI response

    init(vectorSearch: VectorSearchService) {
        self.vectorSearch = vectorSearch
    }

    // Build RAG context from conversation history
    func buildContext(for userQuery: String, libraryId: String? = nil) async throws -> String {
        print("🔨 Building RAG context for query...")

        // 1. Hybrid search for relevant chunks
        var relevantDocs = try await vectorSearch.hybridSearch(query: userQuery, topK: 15)

        // 2. Filter by library if specified
        if let libraryId = libraryId {
            relevantDocs = relevantDocs.filter { doc in
                if let metadata = doc.metadata["library_id"] as? String {
                    return metadata == libraryId
                }
                return false
            }
        }

        // 3. Build context string (token-aware)
        var context = "# Relevant Context from Previous Conversations:\n\n"
        var tokenCount = 0
        var chunksIncluded = 0

        for doc in relevantDocs {
            let chunk = """
            ---
            **Source**: \(doc.sourceType) (relevance: \(String(format: "%.2f", doc.relevanceScore)))
            \(doc.chunkText)


            """

            let chunkTokens = estimateTokens(chunk)

            if tokenCount + chunkTokens > maxContextTokens {
                print("  ⚠️ Reached token limit, stopping at \(chunksIncluded) chunks")
                break
            }

            context += chunk
            tokenCount += chunkTokens
            chunksIncluded += 1
        }

        if chunksIncluded == 0 {
            print("  ℹ️ No relevant context found")
            return ""
        }

        print("  ✅ Built context with \(chunksIncluded) chunks (~\(tokenCount) tokens)")
        return context
    }

    // Rough token estimation (4 chars ≈ 1 token)
    private func estimateTokens(_ text: String) -> Int {
        return text.count / 4
    }
}
```

### 3.5 Update ChatViewModel for RAG

**File**: `XRAiAssistant/ChatViewModel.swift`

```swift
@Published var useRAG: Bool = true // Add toggle in Settings
private var ragContextBuilder: RAGContextBuilder?
private var embeddingService: EmbeddingService?
private var vectorSearchService: VectorSearchService?

// Initialize RAG services
private func initializeRAGServices() {
    let apiKey = aiProviderManager.getAPIKey(for: "Together.ai")
    guard apiKey != "changeMe" else {
        print("⚠️ RAG disabled: API key not configured")
        return
    }

    embeddingService = EmbeddingService(apiKey: apiKey)
    vectorSearchService = VectorSearchService(embeddingService: embeddingService!)
    ragContextBuilder = RAGContextBuilder(vectorSearch: vectorSearchService!)

    print("✅ RAG services initialized")
}

// Update sendMessage to use RAG
func sendMessage(_ content: String, images: [UIImage] = []) async {
    // ... existing code ...

    // Build enhanced system prompt with RAG context
    var enhancedSystemPrompt = systemPrompt

    if useRAG, let ragBuilder = ragContextBuilder {
        do {
            let ragContext = try await ragBuilder.buildContext(
                for: content,
                libraryId: library3DManager.selectedLibrary.id
            )

            if !ragContext.isEmpty {
                enhancedSystemPrompt = """
                \(systemPrompt)

                \(ragContext)

                **Instructions**: Use the context above to inform your responses when relevant. Reference specific examples from previous conversations when applicable.
                """
                print("🎯 RAG context added to system prompt")
            }
        } catch {
            print("⚠️ Failed to build RAG context: \(error)")
        }
    }

    // Call AI with enhanced prompt
    let response = try await callLlamaInference(
        userMessage: content,
        systemPrompt: enhancedSystemPrompt
    )

    // ... rest of existing code ...

    // Index new message for RAG (fire-and-forget)
    if useRAG {
        Task.detached { [weak self] in
            await self?.indexNewMessage(assistantMessage)
        }
    }
}

// Index new message for future RAG queries
private func indexNewMessage(_ message: ChatMessage) async {
    guard let embeddingService = embeddingService else { return }

    do {
        // Create RAG document
        let document = RAGDocument(
            id: UUID().uuidString,
            sourceType: "conversation",
            sourceId: message.id,
            chunkText: message.content,
            chunkIndex: 0,
            metadata: ["library_id": message.libraryId ?? ""]
        )

        // Generate embedding
        let embedding = try await embeddingService.generateEmbedding(text: message.content)

        // Save to database
        try await DatabaseManager.shared.saveRAGDocument(document, embedding: embedding)

        print("✅ Indexed new message for RAG")
    } catch {
        print("⚠️ Failed to index message: \(error)")
    }
}
```

### 3.6 Add RAG Methods to DatabaseManager

**File**: `XRAiAssistant/Database/DatabaseManager.swift`

```swift
// MARK: - RAG CRUD

func saveRAGDocument(_ document: RAGDocument, embedding: [Float]) async throws {
    try await dbQueue.write { db in
        // Save document
        try db.execute(
            sql: """
            INSERT INTO rag_documents (id, source_type, source_id, chunk_text, chunk_index, metadata)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                document.id,
                document.sourceType,
                document.sourceId,
                document.chunkText,
                document.chunkIndex,
                try? JSONEncoder().encode(document.metadata).base64EncodedString()
            ]
        )

        // Save embedding
        let embeddingData = Data(bytes: embedding, count: embedding.count * MemoryLayout<Float>.size)
        try db.execute(
            sql: """
            INSERT INTO rag_embeddings (id, document_id, embedding, embedding_model, dimension)
            VALUES (?, ?, ?, ?, ?)
            """,
            arguments: [
                UUID().uuidString,
                document.id,
                embeddingData,
                "togethercomputer/m2-bert-80M-8k-retrieval",
                embedding.count
            ]
        )

        // Insert into FTS5
        try db.execute(
            sql: "INSERT INTO rag_documents_fts (id, chunk_text) VALUES (?, ?)",
            arguments: [document.id, document.chunkText]
        )
    }
}

struct EmbeddingData {
    let document: RAGDocument
    let embedding: [Float]
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

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

        return rows.compactMap { row -> EmbeddingData? in
            guard let embeddingData = row["embedding"] as? Data else { return nil }

            let embedding = embeddingData.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self))
            }

            let metadataStr: String? = row["metadata"]
            var metadata: [String: Any] = [:]
            if let metadataStr = metadataStr,
               let data = Data(base64Encoded: metadataStr),
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

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

        return rows.map { row in
            let metadataStr: String? = row["metadata"]
            var metadata: [String: Any] = [:]
            if let metadataStr = metadataStr,
               let data = Data(base64Encoded: metadataStr),
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
```

### 3.7 Add RAG Toggle to Settings UI

**File**: `XRAiAssistant/ContentView.swift`

```swift
// In Settings view
Toggle("Enable RAG (Context-Aware AI)", isOn: $chatViewModel.useRAG)
    .onChange(of: chatViewModel.useRAG) { enabled in
        if enabled {
            chatViewModel.initializeRAGServices()
        }
    }
```

### 3.8 Deliverables

- [ ] RAG tables migration (v2_rag_tables) runs successfully
- [ ] `EmbeddingService.swift` integrated with Together AI
- [ ] `VectorSearchService.swift` implements cosine similarity
- [ ] `RAGContextBuilder.swift` assembles context for AI
- [ ] ChatViewModel integrates RAG into message flow
- [ ] Settings UI has RAG toggle
- [ ] Test semantic search with sample conversations
- [ ] Verify embedding generation and storage

---

## Phase 4: Background Indexing

**Duration**: Weeks 4-5
**Goal**: Automatically index conversations without blocking UI

### 4.1 Background Indexer

**File**: `XRAiAssistant/RAG/BackgroundIndexer.swift`

```swift
import Foundation
import BackgroundTasks

class BackgroundIndexer {
    static let shared = BackgroundIndexer()

    private let taskIdentifier = "com.xraiassistant.embeddings"
    private let embeddingService: EmbeddingService?
    private let db = DatabaseManager.shared

    init() {
        // Will be initialized with API key later
        embeddingService = nil
    }

    func configure(apiKey: String) {
        // Reinitialize with API key
    }

    // Register background task in app lifecycle
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundIndexing(task: task as! BGProcessingTask)
        }

        print("✅ Background indexing task registered")
    }

    // Schedule background indexing
    func scheduleBackgroundIndexing() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = true // For API calls
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600) // 1 hour from now

        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background indexing scheduled")
        } catch {
            print("❌ Failed to schedule background indexing: \(error)")
        }
    }

    // Handle background task
    private func handleBackgroundIndexing(task: BGProcessingTask) {
        print("🔄 Background indexing started...")

        task.expirationHandler = {
            print("⚠️ Background indexing expired")
            task.setTaskCompleted(success: false)
        }

        Task {
            do {
                try await indexUnindexedConversations()
                print("✅ Background indexing completed")
                task.setTaskCompleted(success: true)
            } catch {
                print("❌ Background indexing failed: \(error)")
                task.setTaskCompleted(success: false)
            }

            // Schedule next run
            scheduleBackgroundIndexing()
        }
    }

    // Index conversations that don't have embeddings yet
    func indexUnindexedConversations() async throws {
        guard let embeddingService = embeddingService else {
            print("⚠️ Embedding service not configured")
            return
        }

        // Find conversations without embeddings
        let unindexed = try await db.loadUnindexedConversations()

        print("📊 Found \(unindexed.count) unindexed conversations")

        for (index, conversation) in unindexed.enumerated() {
            print("  🔄 Indexing conversation \(index + 1)/\(unindexed.count)...")
            try await chunkAndEmbedConversation(conversation, embeddingService: embeddingService)
        }
    }

    // Chunk conversation and generate embeddings
    private func chunkAndEmbedConversation(_ conversation: Conversation, embeddingService: EmbeddingService) async throws {
        // Smart chunking: group messages into semantic units
        let chunks = createChunks(from: conversation.messages, maxChunkSize: 512)

        print("    📦 Created \(chunks.count) chunks")

        // Batch generate embeddings (up to 20 at a time)
        let batchSize = 20
        for i in stride(from: 0, to: chunks.count, by: batchSize) {
            let endIndex = min(i + batchSize, chunks.count)
            let batch = Array(chunks[i..<endIndex])

            let texts = batch.map { $0.text }
            let embeddings = try await embeddingService.batchGenerateEmbeddings(texts: texts)

            // Save to database
            for (chunk, embedding) in zip(batch, embeddings) {
                let document = RAGDocument(
                    id: UUID().uuidString,
                    sourceType: "conversation",
                    sourceId: conversation.id.uuidString,
                    chunkText: chunk.text,
                    chunkIndex: chunk.index,
                    metadata: [
                        "conversation_title": conversation.title,
                        "library_id": conversation.library3DID ?? ""
                    ]
                )

                try await db.saveRAGDocument(document, embedding: embedding)
            }

            print("      ✅ Indexed batch \(i/batchSize + 1)")
        }
    }

    // Create smart chunks from messages
    private func createChunks(from messages: [EnhancedChatMessage], maxChunkSize: Int) -> [(text: String, index: Int)] {
        var chunks: [(text: String, index: Int)] = []
        var currentChunk = ""
        var chunkIndex = 0

        for message in messages {
            let messageText = "\(message.isUser ? "User" : "Assistant"): \(message.content)\n\n"

            // If adding this message exceeds chunk size, save current chunk and start new one
            if currentChunk.count + messageText.count > maxChunkSize, !currentChunk.isEmpty {
                chunks.append((text: currentChunk, index: chunkIndex))
                currentChunk = ""
                chunkIndex += 1
            }

            currentChunk += messageText
        }

        // Add final chunk
        if !currentChunk.isEmpty {
            chunks.append((text: currentChunk, index: chunkIndex))
        }

        return chunks
    }
}
```

### 4.2 Update DatabaseManager

Add method to find unindexed conversations:

```swift
// MARK: - Background Indexing Support

func loadUnindexedConversations() async throws -> [Conversation] {
    try await dbQueue.read { db in
        // Find conversations that don't have embeddings
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
```

### 4.3 Register Background Tasks in App

**File**: `XRAiAssistant/XRAiAssistant.swift`

```swift
@main
struct XRAiAssistant: App {
    @StateObject private var chatViewModel = ChatViewModel()

    init() {
        // Register background tasks
        BackgroundIndexer.shared.registerBackgroundTasks()

        // Migration on first launch
        Task {
            let migrator = UserDefaultsMigrator()
            if migrator.shouldMigrate() {
                try? await migrator.migrateToSQLite()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chatViewModel)
        }
    }
}
```

### 4.4 Update Info.plist

Add background modes permission:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.xraiassistant.embeddings</string>
</array>
```

### 4.5 Deliverables

- [ ] `BackgroundIndexer.swift` implemented
- [ ] Background task registered in app lifecycle
- [ ] Info.plist updated with background permissions
- [ ] Chunking strategy implemented
- [ ] Batch embedding generation working
- [ ] Test background indexing on device
- [ ] Monitor indexing progress in logs

---

## Phase 5: Advanced Features

**Duration**: Weeks 5-6
**Goal**: Add analytics, export/import, and smart features

### 5.1 Conversation Analytics

**File**: `XRAiAssistant/RAG/ConversationAnalytics.swift`

```swift
import Foundation

class ConversationAnalytics {
    private let db = DatabaseManager.shared
    private let vectorSearch: VectorSearchService

    init(vectorSearch: VectorSearchService) {
        self.vectorSearch = vectorSearch
    }

    // Find most discussed topics using embedding clustering
    func getMostDiscussedTopics(limit: Int = 5) async throws -> [Topic] {
        // Load all embeddings
        let embeddings = try await db.loadAllEmbeddings()

        // K-means clustering to find topic clusters
        let clusters = performKMeansClustering(embeddings: embeddings.map { $0.embedding }, k: limit)

        // Extract representative text from each cluster
        var topics: [Topic] = []
        for (index, cluster) in clusters.enumerated() {
            let clusterDocs = cluster.map { embeddings[$0].document }
            let title = extractTopicTitle(from: clusterDocs)
            topics.append(Topic(id: index, title: title, documentCount: clusterDocs.count))
        }

        return topics
    }

    // Find related conversations
    func getRelatedConversations(to conversationId: UUID, limit: Int = 5) async throws -> [Conversation] {
        // Get conversation's average embedding
        let embeddings = try await db.loadEmbeddingsForConversation(conversationId: conversationId)
        guard !embeddings.isEmpty else { return [] }

        let avgEmbedding = averageEmbedding(embeddings)

        // Find similar conversations
        // ... implementation ...

        return []
    }

    // Helper: K-means clustering (simplified)
    private func performKMeansClustering(embeddings: [[Float]], k: Int) -> [[Int]] {
        // Simplified clustering logic
        return []
    }

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

    private func extractTopicTitle(from documents: [RAGDocument]) -> String {
        // Extract common keywords
        return "Topic \(documents.count)"
    }
}

struct Topic {
    let id: Int
    let title: String
    let documentCount: Int
}
```

### 5.2 Export/Import

**File**: `XRAiAssistant/Services/DatabaseExporter.swift`

```swift
import Foundation

class DatabaseExporter {
    private let db = DatabaseManager.shared

    // Export entire database to JSON
    func exportToJSON() async throws -> URL {
        print("📤 Exporting database to JSON...")

        // Load all data
        let conversations = try await db.loadConversations(limit: Int.max)
        let settings = try await loadAllSettings()

        let exportData: [String: Any] = [
            "version": 1,
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "conversations": try conversations.map { try encodeConversation($0) },
            "settings": settings
        ]

        // Write to file
        let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("XRAiAssistant_Export_\(Date().timeIntervalSince1970).json")

        try jsonData.write(to: tempURL)

        print("✅ Exported to: \(tempURL.path)")
        return tempURL
    }

    // Import from JSON backup
    func importFromJSON(_ url: URL) async throws {
        print("📥 Importing from JSON: \(url.path)")

        let jsonData = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ExportError.invalidFormat
        }

        // Restore conversations
        if let conversationsData = json["conversations"] as? [[String: Any]] {
            for convData in conversationsData {
                let conversation = try decodeConversation(from: convData)
                try await db.saveConversation(conversation)
            }
        }

        // Restore settings
        if let settings = json["settings"] as? [String: Any] {
            for (key, value) in settings {
                try await db.saveSetting(key: key, value: value)
            }
        }

        print("✅ Import complete")
    }

    private func loadAllSettings() async throws -> [String: Any] {
        // Implementation
        return [:]
    }

    private func encodeConversation(_ conversation: Conversation) throws -> [String: Any] {
        // Implementation
        return [:]
    }

    private func decodeConversation(from data: [String: Any]) throws -> Conversation {
        // Implementation
        fatalError("Not implemented")
    }
}

enum ExportError: Error {
    case invalidFormat
}
```

### 5.3 Deliverables

- [ ] `ConversationAnalytics.swift` implements topic discovery
- [ ] `DatabaseExporter.swift` supports JSON export/import
- [ ] Add export/import buttons to Settings UI
- [ ] Test export/import workflow
- [ ] Document advanced features in README

---

## Implementation Checklist

### Phase 1: SQLite Foundation ✅
- [ ] Add GRDB.swift dependency (v7.0.0+)
- [ ] Create `XRAiAssistant/Database/` directory
- [ ] Implement `DatabaseManager.swift`
- [ ] Define schema in migrations (v1_initial_schema)
- [ ] Write unit tests for CRUD operations
- [ ] Verify build succeeds

### Phase 2: Data Migration ✅
- [ ] Implement `UserDefaultsMigrator.swift`
- [ ] Update `XRAiAssistant.swift` to run migration
- [ ] Update `ChatViewModel.swift` to use SQLite
- [ ] Update `ConversationStorageManager.swift` to use SQLite
- [ ] Test migration with existing user data
- [ ] Verify backwards compatibility

### Phase 3: RAG System ✅
- [ ] Enable `v2_rag_tables` migration
- [ ] Implement `EmbeddingService.swift`
- [ ] Implement `VectorSearchService.swift`
- [ ] Implement `RAGContextBuilder.swift`
- [ ] Add RAG methods to `DatabaseManager.swift`
- [ ] Integrate RAG into `ChatViewModel`
- [ ] Add RAG toggle to Settings UI
- [ ] Test semantic search accuracy

### Phase 4: Background Indexing ✅
- [ ] Implement `BackgroundIndexer.swift`
- [ ] Register background task in app lifecycle
- [ ] Update `Info.plist` with background permissions
- [ ] Implement chunking strategy
- [ ] Add batch embedding support
- [ ] Test on physical device
- [ ] Monitor indexing performance

### Phase 5: Advanced Features ✅
- [ ] Implement `ConversationAnalytics.swift`
- [ ] Implement `DatabaseExporter.swift`
- [ ] Add export/import to Settings
- [ ] Test all advanced features
- [ ] Update documentation

---

## Technical Decisions

### Why GRDB.swift?

✅ **Pros**:
- Pure Swift (no Objective-C bridging)
- Type-safe query builder
- Built-in FTS5 full-text search
- Reactive @Published integration
- Migration system
- Async/await support
- Well-maintained

❌ **Alternatives Considered**:
- CoreData: Too complex, Objective-C legacy
- Realm: Separate database engine, larger footprint
- SQLite.swift: Less feature-rich than GRDB

### Why Together AI for Embeddings?

✅ **Pros**:
- Already integrated
- Free tier available
- `m2-bert-80M-8k-retrieval`:
  - 768 dimensions (good balance)
  - 8K context length
  - Optimized for retrieval

❌ **Alternatives**:
- OpenAI Embeddings: More expensive
- Local models: Slower, larger app size
- Google Vertex AI: Requires GCP setup

### Why Hybrid Search?

✅ **Benefits**:
- FTS5 for exact keyword matches (fast)
- Vector search for semantic similarity
- Combined scoring = best results
- Fallback if one method fails

### Storage Estimates

```
Average User:
├── Conversations: 100 conversations × 50 messages × 500 chars = 2.5MB
├── Embeddings: 5,000 messages × 768 floats × 4 bytes = 15MB
├── Images: 50 images × 500KB (compressed) = 25MB
└── Total: ~42.5MB

Power User:
├── Conversations: 1,000 conversations × 100 messages × 1,000 chars = 100MB
├── Embeddings: 100,000 messages × 768 floats × 4 bytes = 300MB
├── Images: 500 images × 500KB = 250MB
└── Total: ~650MB
```

---

## Performance

### Optimization Strategies

1. **Lazy Embedding**: Only generate when RAG enabled
2. **Batch API Calls**: 10-20 embeddings per request
3. **FTS5 Pre-filtering**: Reduce vector search candidates
4. **Memory Caching**: Cache recent embeddings
5. **Quantization**: Int8 embeddings = 4× smaller (future)
6. **Pagination**: Load conversations in batches

### Benchmarks (Target)

- Conversation load: < 200ms
- Full-text search: < 100ms
- Semantic search: < 2s (1,000+ messages)
- Embedding generation: < 500ms per message
- Background indexing: 10 messages/minute

---

## Security

### API Key Protection

**Current**: UserDefaults (not secure)
**Phase 3**: iOS Keychain

```swift
import Security

class KeychainManager {
    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        if let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}
```

### Database Encryption (Optional)

Use **SQLCipher** for full database encryption:

```swift
var config = Configuration()
config.prepareDatabase { db in
    try db.execute(sql: "PRAGMA key = '\(encryptionKey)'")
}
dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
```

### Secure Deletion

```sql
-- Secure delete with overwrite
PRAGMA secure_delete = ON;
```

---

## Testing

### Unit Tests

**File**: `XRAiAssistantTests/DatabaseTests/`

```
DatabaseTests/
├── DatabaseManagerTests.swift
├── EmbeddingServiceTests.swift
├── VectorSearchTests.swift
├── RAGContextBuilderTests.swift
└── MigrationTests.swift
```

**Example**:

```swift
import XCTest
@testable import XRAiAssistant

class DatabaseManagerTests: XCTestCase {
    var db: DatabaseManager!

    override func setUp() {
        db = DatabaseManager.shared
    }

    func testSaveSetting() async throws {
        try await db.saveSetting(key: "test_key", value: "test_value")
        let loaded = try await db.loadSetting(key: "test_key") as? String
        XCTAssertEqual(loaded, "test_value")
    }

    func testSaveConversation() async throws {
        let conversation = Conversation(
            id: UUID(),
            title: "Test",
            messages: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        try await db.saveConversation(conversation)
        let loaded = try await db.loadConversations(limit: 1)
        XCTAssertEqual(loaded.first?.id, conversation.id)
    }
}
```

### Integration Tests

```swift
class RAGIntegrationTests: XCTestCase {
    func testEndToEndRAG() async throws {
        // 1. Save conversation
        // 2. Generate embeddings
        // 3. Perform semantic search
        // 4. Verify results
    }
}
```

---

## Success Metrics

- ✅ 100% data migrated from UserDefaults
- ✅ Zero data loss during migration
- ✅ < 200ms conversation load time
- ✅ < 2s semantic search (1,000+ messages)
- ✅ < 5% app size increase
- ✅ RAG improves response relevance (qualitative)
- ✅ Background indexing doesn't impact battery

---

## Troubleshooting

### Migration Fails

**Issue**: Migration crashes or data missing

**Solution**:
1. Check migration logs
2. Verify UserDefaults data format
3. Add error recovery in migrator
4. Test with sample data first

### Embeddings API Errors

**Issue**: Together AI returns 401/429

**Solution**:
1. Verify API key is valid
2. Check rate limits (free tier)
3. Add retry logic with exponential backoff
4. Cache embeddings to reduce calls

### Slow Search Performance

**Issue**: Semantic search takes > 5s

**Solution**:
1. Enable FTS5 pre-filtering
2. Reduce topK limit
3. Add database indexes
4. Consider embedding quantization

---

## Future Enhancements

### Phase 6+

- [ ] Embedding quantization (Int8) for 4× size reduction
- [ ] Multi-modal RAG (image + text search)
- [ ] Conversation summarization using AI
- [ ] Auto-tagging with topic detection
- [ ] Cross-device sync (iCloud)
- [ ] Advanced analytics dashboard
- [ ] RAG quality metrics (precision/recall)
- [ ] Custom embedding models

---

## Resources

- [GRDB.swift Documentation](https://github.com/groue/GRDB.swift)
- [SQLite FTS5 Guide](https://www.sqlite.org/fts5.html)
- [Together AI Embeddings API](https://docs.together.ai/reference/embeddings)
- [iOS Background Tasks](https://developer.apple.com/documentation/backgroundtasks)
- [RAG Best Practices](https://www.pinecone.io/learn/retrieval-augmented-generation/)

---

**Last Updated**: 2025-11-29
**Status**: Ready for Implementation
**Next Step**: Begin Phase 1 - SQLite Foundation
