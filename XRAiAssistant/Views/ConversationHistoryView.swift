import SwiftUI

// MARK: - Conversation History View
struct ConversationHistoryView: View {
    @ObservedObject var storageManager: ConversationStorageManager
    @Binding var isPresented: Bool
    @Binding var selectedConversation: Conversation?

    @State private var searchText = ""
    @State private var showingClearAlert = false

    var body: some View {
        NavigationView {
            ZStack {
                if filteredConversations.isEmpty {
                    emptyStateView
                } else {
                    conversationList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        MaigeXRBrandText(isActive: true, fontSize: 17)
                        Text("History")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showingClearAlert = true
                        } label: {
                            Label("Clear All History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search conversations")
            .alert("Clear All History?", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    storageManager.clearAllConversations()
                }
            } message: {
                Text("This will permanently delete all saved conversations. This action cannot be undone.")
            }
        }
    }

    private var conversationList: some View {
        List {
            ForEach(filteredConversations) { conversation in
                ConversationRowView(conversation: conversation)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedConversation = conversation
                        isPresented = false
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            storageManager.deleteConversation(conversation.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 64))
                .foregroundColor(.gray)

            Text("No Conversations Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text(searchText.isEmpty
                 ? "Start a new conversation to see it here"
                 : "No conversations match your search")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return storageManager.conversations
        } else {
            return storageManager.searchConversations(query: searchText)
        }
    }
}

// MARK: - Conversation Row View
struct ConversationRowView: View {
    let conversation: Conversation

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Screenshot thumbnail (left side - matching Android implementation)
            ConversationThumbnailView(screenshotBase64: conversation.screenshotBase64)

            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(2)

                // Preview of first AI response
                if let firstAIMessage = conversation.messages.first(where: { !$0.isUser }) {
                    Text(firstAIMessage.content)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Metadata
                HStack(spacing: 12) {
                    Label(relativeDateString(from: conversation.updatedAt), systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("\(conversation.messages.count)", systemImage: "bubble.left.and.bubble.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let library = conversation.library3DID {
                        Text(library)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }

                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Conversation Thumbnail View
struct ConversationThumbnailView: View {
    let screenshotBase64: String?

    var body: some View {
        Group {
            if let base64String = screenshotBase64, let uiImage = decodeBase64ToUIImage(base64String) {
                // Display screenshot thumbnail
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.neonCyan, lineWidth: 1.5)
                    )
                    .neonGlow(color: .neonCyan, radius: 4)
            } else {
                // Placeholder icon when no screenshot
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.cyberpunkDarkGray.opacity(0.3))
                        .frame(width: 80, height: 80)

                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundColor(.neonCyan.opacity(0.5))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.neonCyan.opacity(0.5), lineWidth: 1.5)
                )
            }
        }
    }

    /// Decode base64 string to UIImage (matching Android's Base64.decode)
    private func decodeBase64ToUIImage(_ base64String: String) -> UIImage? {
        // Remove data URL prefix if present (like Android implementation)
        var cleanedBase64 = base64String
            .replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
            .replacingOccurrences(of: "data:image/png;base64,", with: "")

        // Decode base64 to Data
        guard let imageData = Data(base64Encoded: cleanedBase64) else {
            print("⚠️ Failed to decode screenshot base64")
            return nil
        }

        // Create UIImage from data
        guard let image = UIImage(data: imageData) else {
            print("⚠️ Failed to create UIImage from screenshot data")
            return nil
        }

        return image
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @StateObject var storage = ConversationStorageManager()
        @State var isPresented = true
        @State var selectedConversation: Conversation? = nil

        var body: some View {
            ConversationHistoryView(
                storageManager: storage,
                isPresented: $isPresented,
                selectedConversation: $selectedConversation
            )
            .onAppear {
                // Add sample conversations
                let conv1 = Conversation(
                    title: "Creating a 3D Cube",
                    messages: [
                        EnhancedChatMessage(content: "How do I create a rotating cube in Three.js?", isUser: true),
                        EnhancedChatMessage(content: "Here's how to create a rotating cube:\n\n```javascript\nconst geometry = new THREE.BoxGeometry(1, 1, 1);\nconst material = new THREE.MeshBasicMaterial({ color: 0x00ff00 });\nconst cube = new THREE.Mesh(geometry, material);\nscene.add(cube);\n```", isUser: false)
                    ],
                    library3DID: "threejs"
                )
                storage.addConversation(conv1)

                let conv2 = Conversation(
                    title: "Babylon.js Lighting",
                    messages: [
                        EnhancedChatMessage(content: "Add dynamic lighting to my scene", isUser: true),
                        EnhancedChatMessage(content: "I'll help you add **point lights** with animation.", isUser: false)
                    ],
                    library3DID: "babylonjs"
                )
                storage.addConversation(conv2)
            }
        }
    }

    return PreviewWrapper()
}
