//
//  FavoritesView.swift
//  m{ai}geXR
//
//  Favorites list view - displays bookmarked code snippets
//  Users can search, view, run, and delete favorites
//

import SwiftUI

struct FavoritesView: View {
    @ObservedObject var storageManager: ConversationStorageManager
    @Binding var isPresented: Bool
    @Binding var selectedFavorite: Favorite?

    @State private var favorites: [Favorite] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingClearAlert = false

    var filteredFavorites: [Favorite] {
        if searchText.isEmpty {
            return favorites
        }
        return favorites.filter { favorite in
            favorite.matches(searchText: searchText)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading favorites...")
                        .foregroundColor(.brandAccentText)
                } else if favorites.isEmpty {
                    emptyStateView
                } else {
                    favoritesList
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(.brandAccentText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showingClearAlert = true
                        } label: {
                            Label("Clear All Favorites", systemImage: "trash")
                        }
                        .disabled(favorites.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.brandAccentText)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search favorites")
            .task {
                await loadFavorites()
            }
            .refreshable {
                await loadFavorites()
            }
            .alert("Clear All Favorites?", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    clearAllFavorites()
                }
            } message: {
                Text("This will delete all your favorited scenes. This action cannot be undone.")
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Subviews

    private var favoritesList: some View {
        List {
            ForEach(filteredFavorites) { favorite in
                FavoriteRowView(favorite: favorite, displayTitle: displayTitle(for: favorite))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedFavorite = favorite
                        isPresented = false
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteFavorite(favorite)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    /// Favorites saved before titles came from the scene name carry the first
    /// line of code ("let S;"). Show the name from the original reply instead,
    /// when that reply is still in history.
    private func displayTitle(for favorite: Favorite) -> String? {
        guard favorite.title == SceneText.legacyTitle(fromCode: favorite.codeContent) else { return nil }
        let reply = storageManager.conversations
            .first { $0.id == favorite.conversationId }?
            .messages.first { $0.id == favorite.messageId }?
            .content
        return SceneText.title(fromReply: reply)
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "star")
                .font(.system(size: 40, weight: .regular))
                .foregroundColor(.brandMuted)

            Text("No favorites yet")
                .font(.headline)
                .foregroundColor(.brandText)

            Text("Tap the star on an AI reply with code to keep it here")
                .font(.subheadline)
                .foregroundColor(.brandMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadFavorites() async {
        isLoading = true
        do {
            favorites = try await storageManager.loadFavorites()
            isLoading = false
            print("📋 Loaded \(favorites.count) favorites")
        } catch {
            errorMessage = "Failed to load favorites: \(error.localizedDescription)"
            isLoading = false
            print("❌ Error loading favorites: \(error)")
        }
    }

    private func deleteFavorite(_ favorite: Favorite) {
        Task {
            do {
                try await storageManager.deleteFavorite(id: favorite.id)
                await loadFavorites()
            } catch {
                errorMessage = "Failed to delete favorite: \(error.localizedDescription)"
            }
        }
    }

    private func clearAllFavorites() {
        Task {
            do {
                try await storageManager.clearAllFavorites()
                await loadFavorites()
            } catch {
                errorMessage = "Failed to clear favorites: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Favorite Row View

struct FavoriteRowView: View {
    let favorite: Favorite
    /// The title to show, which may be better than the stored one.
    var displayTitle: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ConversationThumbnailView(screenshotBase64: favorite.screenshotBase64)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle ?? favorite.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.brandText)
                    .lineLimit(1)

                Text(favorite.previewText)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.brandMuted)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text([favorite.formattedDate, favorite.modelUsed].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.brandMuted)

                    if let library = favorite.libraryId {
                        Text(library)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.brandAccentText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.brandAccent.opacity(0.10)))
                    }
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    FavoritesView(
        storageManager: ConversationStorageManager(),
        isPresented: .constant(true),
        selectedFavorite: .constant(nil)
    )
}
