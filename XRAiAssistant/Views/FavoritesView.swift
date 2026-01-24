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
                        .foregroundColor(.neonCyan)
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
                    .foregroundColor(.neonCyan)
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
                            .foregroundColor(.neonCyan)
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
                FavoriteRowView(favorite: favorite)
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
        .listStyle(.plain)
        .background(Color.cyberpunkBlack)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "star.slash")
                .font(.system(size: 64))
                .foregroundColor(.cyberpunkGray)

            Text("No Favorites Yet")
                .font(.title2)
                .foregroundColor(.cyberpunkWhite)

            Text("Tap the star icon on any code message to add it to your favorites")
                .font(.body)
                .foregroundColor(.cyberpunkGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cyberpunkBlack)
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail
            if let base64 = favorite.screenshotBase64,
               let imageData = Data(base64Encoded: base64),
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.neonCyan.opacity(0.3), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.cyberpunkDarkGray)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.cyberpunkGray)
                            .font(.title2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.cyberpunkGray.opacity(0.3), lineWidth: 1)
                    )
            }

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(favorite.title)
                    .font(.headline)
                    .foregroundColor(.neonCyan)
                    .lineLimit(2)

                Text(favorite.previewText)
                    .font(.caption)
                    .foregroundColor(.cyberpunkGray)
                    .lineLimit(2)
                    .fontDesign(.monospaced)

                HStack(spacing: 8) {
                    if let library = favorite.libraryId {
                        Label(library, systemImage: "cube")
                            .font(.caption2)
                            .foregroundColor(.neonPink)
                    }

                    if let model = favorite.modelUsed {
                        Label(model, systemImage: "brain")
                            .font(.caption2)
                            .foregroundColor(.neonBlue)
                    }

                    Spacer()

                    Text(favorite.formattedDate)
                        .font(.caption2)
                        .foregroundColor(.cyberpunkGray)
                }
            }

            Spacer()

            Image(systemName: "star.fill")
                .foregroundColor(.warningNeon)
                .font(.title3)
        }
        .padding(.vertical, 8)
        .background(Color.cyberpunkBlack)
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
