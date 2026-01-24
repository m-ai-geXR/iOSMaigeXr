//
//  FavoriteModels.swift
//  m{ai}geXR
//
//  Data models for the Favorites system
//  Allows users to bookmark individual AI-generated code snippets
//

import Foundation

// MARK: - Favorite Model

struct Favorite: Identifiable, Codable, Equatable {
    let id: UUID
    let messageId: UUID
    let conversationId: UUID
    var title: String
    let codeContent: String
    let libraryId: String?
    let modelUsed: String?
    var screenshotBase64: String?
    let createdAt: Date
    var favoriteOrder: Int?
    var tags: [String]?

    // MARK: - Computed Properties

    /// Preview text (first 3 lines of code)
    var previewText: String {
        let lines = codeContent.components(separatedBy: .newlines)
        return lines.prefix(3).joined(separator: "\n")
    }

    /// Formatted relative date (e.g., "5 min ago", "2 hrs ago")
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    /// Short title for display (max 50 characters)
    var shortTitle: String {
        if title.count > 50 {
            return String(title.prefix(47)) + "..."
        }
        return title
    }

    // MARK: - Codable Keys

    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case conversationId = "conversation_id"
        case title
        case codeContent = "code_content"
        case libraryId = "library_id"
        case modelUsed = "model_used"
        case screenshotBase64 = "screenshot_base64"
        case createdAt = "created_at"
        case favoriteOrder = "favorite_order"
        case tags
    }
}

// MARK: - Favorite Helpers

extension Favorite {
    /// Check if this favorite matches a search query
    func matches(searchText: String) -> Bool {
        if searchText.isEmpty { return true }

        let lowercaseQuery = searchText.lowercased()
        return title.lowercased().contains(lowercaseQuery) ||
               codeContent.lowercased().contains(lowercaseQuery) ||
               (libraryId?.lowercased().contains(lowercaseQuery) ?? false)
    }
}
