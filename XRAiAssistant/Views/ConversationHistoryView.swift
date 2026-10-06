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

    /// The first assistant reply after the user's first message; the welcome
    /// message comes before it and says nothing about the scene.
    private var firstReply: String? {
        guard let firstUser = conversation.messages.firstIndex(where: { $0.isUser }) else { return nil }
        return conversation.messages[(firstUser + 1)...].first(where: { !$0.isUser })?.content
    }

    private var userMessageCount: Int {
        conversation.messages.filter { $0.isUser }.count
    }

    var body: some View {
        let reply = firstReply
        let sceneTitle = SceneText.title(fromReply: reply)
        HStack(alignment: .center, spacing: 12) {
            ConversationThumbnailView(screenshotBase64: conversation.screenshotBase64)

            VStack(alignment: .leading, spacing: 3) {
                // Name the row after the scene when the reply named it; prompts
                // make poor titles.
                Text(sceneTitle ?? conversation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.brandText)
                    .lineLimit(1)

                if let preview = SceneText.preview(of: reply, droppingTitle: sceneTitle) {
                    Text(preview)
                        .font(.footnote)
                        .foregroundColor(.brandMuted)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text("\(relativeDateString(from: conversation.updatedAt)) · \(userMessageCount) prompt\(userMessageCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.brandMuted)

                    if let library = conversation.library3DID {
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
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Quiet placeholder when there is no screenshot yet.
                Image(systemName: "cube.transparent")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(.brandMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.brandSurface)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
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
