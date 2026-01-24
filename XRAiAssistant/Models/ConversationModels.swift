import Foundation
import GRDB

// MARK: - Enhanced Chat Message with Threading Support
struct EnhancedChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let isUser: Bool
    let timestamp: Date
    var threadParentID: UUID? // Reference to parent message for threading
    var replies: [UUID] // Child message IDs
    var libraryId: String? // Track which 3D library was active when this message was created

    init(id: UUID = UUID(), content: String, isUser: Bool, timestamp: Date = Date(), threadParentID: UUID? = nil, replies: [UUID] = [], libraryId: String? = nil) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.threadParentID = threadParentID
        self.replies = replies
        self.libraryId = libraryId
    }

    // Convert from legacy ChatMessage
    init(from legacyMessage: ChatMessage) {
        self.id = UUID()
        self.content = legacyMessage.content
        self.isUser = legacyMessage.isUser
        self.timestamp = legacyMessage.timestamp
        self.threadParentID = nil
        self.replies = []
        self.libraryId = legacyMessage.libraryId
    }
}

// MARK: - Conversation Thread
struct Conversation: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var messages: [EnhancedChatMessage]
    let createdAt: Date
    var updatedAt: Date
    var library3DID: String? // Associated 3D library for context
    var modelUsed: String? // AI model used in this conversation
    var screenshotBase64: String? // Scene screenshot thumbnail (base64-encoded JPEG)

    init(id: UUID = UUID(), title: String, messages: [EnhancedChatMessage] = [], createdAt: Date = Date(), updatedAt: Date = Date(), library3DID: String? = nil, modelUsed: String? = nil, screenshotBase64: String? = nil) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.library3DID = library3DID
        self.modelUsed = modelUsed
        self.screenshotBase64 = screenshotBase64
    }

    // Auto-generate title from first user message
    mutating func generateTitleIfNeeded() {
        if title.isEmpty || title == "New Conversation" {
            if let firstUserMessage = messages.first(where: { $0.isUser }) {
                let content = firstUserMessage.content
                let maxLength = 50
                if content.count > maxLength {
                    title = String(content.prefix(maxLength)) + "..."
                } else {
                    title = content
                }
            }
        }
    }

    // Get top-level messages (not replies)
    func getTopLevelMessages() -> [EnhancedChatMessage] {
        return messages.filter { $0.threadParentID == nil }
    }

    // Get replies for a specific message
    func getReplies(for messageID: UUID) -> [EnhancedChatMessage] {
        return messages.filter { $0.threadParentID == messageID }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // Check if a message has replies
    func hasReplies(_ messageID: UUID) -> Bool {
        return messages.contains { $0.threadParentID == messageID }
    }
}

// MARK: - Conversation Storage Manager
@MainActor
class ConversationStorageManager: ObservableObject {
    @Published var conversations: [Conversation] = []

    private let storageKey = "XRAiAssistant_Conversations"
    private let maxStoredConversations = 100
    private let db = DatabaseManager.shared
    private let useSQLite = true // Toggle for gradual rollout

    init() {
        Task {
            await loadConversations()
        }
    }

    // MARK: - Persistence (SQLite)

    func saveConversations() async {
        if useSQLite {
            // SQLite auto-saves individual conversations
            // This method is kept for compatibility
            print("💾 Conversations auto-saved to SQLite")
        } else {
            saveConversationsUserDefaults()
        }
    }

    func loadConversations() async {
        if useSQLite {
            await loadConversationsSQLite()
        } else {
            loadConversationsUserDefaults()
        }
    }

    // MARK: - SQLite Implementation

    private func loadConversationsSQLite() async {
        do {
            conversations = try await db.loadConversations(limit: maxStoredConversations)
            print("📂 Loaded \(conversations.count) conversations from SQLite")
        } catch {
            print("❌ Failed to load conversations from SQLite: \(error)")
            // Fallback to UserDefaults
            loadConversationsUserDefaults()
        }
    }

    // MARK: - Legacy UserDefaults Implementation (Backup)

    private func saveConversationsUserDefaults() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(conversations)
            UserDefaults.standard.set(data, forKey: storageKey)
            print("💾 Saved \(conversations.count) conversations to UserDefaults")
        } catch {
            print("❌ Failed to save conversations: \(error.localizedDescription)")
        }
    }

    private func loadConversationsUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            print("📂 No saved conversations found in UserDefaults")
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            conversations = try decoder.decode([Conversation].self, from: data)
            print("📂 Loaded \(conversations.count) conversations from UserDefaults")
        } catch {
            print("❌ Failed to load conversations: \(error.localizedDescription)")
            conversations = []
        }
    }

    // MARK: - Conversation Management

    func addConversation(_ conversation: Conversation) {
        var newConversation = conversation
        newConversation.generateTitleIfNeeded()
        conversations.insert(newConversation, at: 0) // Most recent first

        // Limit stored conversations
        if conversations.count > maxStoredConversations {
            conversations = Array(conversations.prefix(maxStoredConversations))
        }

        if useSQLite {
            Task {
                do {
                    try await db.saveConversation(newConversation)
                    print("✅ Conversation saved to SQLite")
                } catch {
                    print("❌ Failed to save conversation: \(error)")
                }
            }
        } else {
            saveConversationsUserDefaults()
        }
    }

    func updateConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            var updated = conversation
            updated.updatedAt = Date()
            updated.generateTitleIfNeeded()
            conversations[index] = updated

            // Move to top (most recent)
            let removed = conversations.remove(at: index)
            conversations.insert(removed, at: 0)

            if useSQLite {
                Task {
                    do {
                        try await db.saveConversation(updated)
                        print("✅ Conversation updated in SQLite")
                    } catch {
                        print("❌ Failed to update conversation: \(error)")
                    }
                }
            } else {
                saveConversationsUserDefaults()
            }
        }
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }

        if useSQLite {
            Task {
                do {
                    try await db.deleteConversation(id)
                    print("✅ Conversation deleted from SQLite")
                } catch {
                    print("❌ Failed to delete conversation: \(error)")
                }
            }
        } else {
            saveConversationsUserDefaults()
        }
    }

    func clearAllConversations() {
        let conversationIds = conversations.map { $0.id }
        conversations.removeAll()

        if useSQLite {
            Task {
                for id in conversationIds {
                    try? await db.deleteConversation(id)
                }
                print("✅ All conversations cleared from SQLite")
            }
        } else {
            saveConversationsUserDefaults()
        }
    }

    func getConversation(id: UUID) -> Conversation? {
        return conversations.first { $0.id == id }
    }

    // MARK: - Search & Filter

    func searchConversations(query: String) -> [Conversation] {
        guard !query.isEmpty else { return conversations }

        return conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(query) ||
            conversation.messages.contains { message in
                message.content.localizedCaseInsensitiveContains(query)
            }
        }
    }

    func getConversationsByLibrary(_ libraryID: String) -> [Conversation] {
        return conversations.filter { $0.library3DID == libraryID }
    }

    func getConversationsByModel(_ modelName: String) -> [Conversation] {
        return conversations.filter { $0.modelUsed == modelName }
    }

    // MARK: - Screenshot Management

    /// Update conversation with screenshot thumbnail
    /// Called after 3D scene renders and screenshot is captured from WebView canvas
    func updateConversationScreenshot(conversationId: UUID, screenshotBase64: String) {
        guard var conversation = getConversation(id: conversationId) else {
            print("⚠️ Cannot update screenshot: Conversation \(conversationId) not found")
            return
        }

        // Update screenshot field
        conversation.screenshotBase64 = screenshotBase64
        conversation.updatedAt = Date()

        // Update in array
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[index] = conversation

            // Move to top (most recent)
            let removed = conversations.remove(at: index)
            conversations.insert(removed, at: 0)
        }

        // Persist to database
        if useSQLite {
            Task {
                do {
                    try await db.saveConversation(conversation)
                    print("✅ Screenshot saved for conversation: \(conversationId)")
                    print("📊 Screenshot size: \(screenshotBase64.count) characters")
                } catch {
                    print("❌ Failed to save screenshot: \(error)")
                }
            }
        } else {
            saveConversationsUserDefaults()
        }
    }

    // MARK: - Favorites Management

    func saveFavorite(
        messageId: UUID,
        conversationId: UUID,
        title: String,
        codeContent: String,
        libraryId: String?,
        modelUsed: String?,
        screenshotBase64: String?
    ) async throws {
        guard let dbQueue = db.dbQueue else {
            throw NSError(domain: "ConversationStorage", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Database not initialized"])
        }

        let favorite = Favorite(
            id: UUID(),
            messageId: messageId,
            conversationId: conversationId,
            title: title,
            codeContent: codeContent,
            libraryId: libraryId,
            modelUsed: modelUsed,
            screenshotBase64: screenshotBase64,
            createdAt: Date(),
            favoriteOrder: nil,
            tags: nil
        )

        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO favorites (id, message_id, conversation_id, title, code_content,
                                     library_id, model_used, screenshot_base64, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                favorite.id.uuidString,
                favorite.messageId.uuidString,
                favorite.conversationId.uuidString,
                favorite.title,
                favorite.codeContent,
                favorite.libraryId,
                favorite.modelUsed,
                favorite.screenshotBase64,
                favorite.createdAt
            ])
        }

        print("⭐ Favorite saved: \(favorite.title)")
    }

    func loadFavorites() async throws -> [Favorite] {
        guard let dbQueue = db.dbQueue else {
            return []
        }

        return try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM favorites
                ORDER BY created_at DESC
            """)

            return rows.compactMap { row in
                guard let id = UUID(uuidString: row["id"]),
                      let messageId = UUID(uuidString: row["message_id"]),
                      let conversationId = UUID(uuidString: row["conversation_id"]),
                      let title: String = row["title"],
                      let codeContent: String = row["code_content"],
                      let createdAt: Date = row["created_at"] else {
                    return nil
                }

                let tagsString: String? = row["tags"]
                let tags = tagsString?.components(separatedBy: ",").filter { !$0.isEmpty }

                return Favorite(
                    id: id,
                    messageId: messageId,
                    conversationId: conversationId,
                    title: title,
                    codeContent: codeContent,
                    libraryId: row["library_id"],
                    modelUsed: row["model_used"],
                    screenshotBase64: row["screenshot_base64"],
                    createdAt: createdAt,
                    favoriteOrder: row["favorite_order"],
                    tags: tags
                )
            }
        }
    }

    func deleteFavorite(id: UUID) async throws {
        guard let dbQueue = db.dbQueue else {
            throw NSError(domain: "ConversationStorage", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Database not initialized"])
        }

        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM favorites WHERE id = ?", arguments: [id.uuidString])
        }
        print("🗑️ Favorite deleted: \(id)")
    }

    func isFavorited(messageId: UUID) async throws -> Bool {
        guard let dbQueue = db.dbQueue else {
            return false
        }

        return try await dbQueue.read { db in
            let count = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM favorites WHERE message_id = ?
            """, arguments: [messageId.uuidString])
            return (count ?? 0) > 0
        }
    }

    func getFavoriteByMessageId(messageId: UUID) async throws -> Favorite? {
        guard let dbQueue = db.dbQueue else {
            return nil
        }

        return try await dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM favorites WHERE message_id = ? LIMIT 1
            """, arguments: [messageId.uuidString]) else {
                return nil
            }

            guard let id = UUID(uuidString: row["id"]),
                  let messageId = UUID(uuidString: row["message_id"]),
                  let conversationId = UUID(uuidString: row["conversation_id"]),
                  let title: String = row["title"],
                  let codeContent: String = row["code_content"],
                  let createdAt: Date = row["created_at"] else {
                return nil
            }

            let tagsString: String? = row["tags"]
            let tags = tagsString?.components(separatedBy: ",").filter { !$0.isEmpty }

            return Favorite(
                id: id,
                messageId: messageId,
                conversationId: conversationId,
                title: title,
                codeContent: codeContent,
                libraryId: row["library_id"],
                modelUsed: row["model_used"],
                screenshotBase64: row["screenshot_base64"],
                createdAt: createdAt,
                favoriteOrder: row["favorite_order"],
                tags: tags
            )
        }
    }

    func clearAllFavorites() async throws {
        guard let dbQueue = db.dbQueue else {
            throw NSError(domain: "ConversationStorage", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Database not initialized"])
        }

        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM favorites")
        }
        print("🗑️ All favorites cleared")
    }
}
