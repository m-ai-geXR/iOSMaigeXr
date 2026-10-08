import SwiftUI
import PhotosUI

// MARK: - Enhanced Chat View with Adaptive Layout
struct EnhancedChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject private var appearance = AppearanceStore.shared
    private var theme: ChatTheme { appearance.chatTheme }
    @ObservedObject var storageManager: ConversationStorageManager
    var onRunCode: ((_ code: String, _ libraryId: String?) -> Void)?

    @State private var currentConversation: Conversation?
    @State private var expandedThreads: Set<UUID> = []
    @State private var replyingToMessageID: UUID?
    @State private var inputText = ""
    @State private var showHistory = false
    @State private var selectedHistoryConversation: Conversation?
    @State private var isCompactView = false

    // Favorites support
    @State private var showFavorites = false
    @State private var selectedFavorite: Favorite?
    @State private var favoritedMessageIds: Set<UUID> = []

    // Image attachment support
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    // Adaptive layout properties
    private var isWideLayout: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

    private var maxMessageWidth: CGFloat {
        if isCompactView {
            return 600
        } else if isWideLayout {
            return 900 // Wider for iPad
        } else {
            return 600
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Model and Library selectors header (always visible)
                modelAndLibraryHeader

                // Conversation header (if loaded from history)
                if let conversation = currentConversation {
                    conversationHeaderView(conversation)
                }

                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if let conversation = currentConversation {
                                // Threaded conversation view
                                ForEach(conversation.getTopLevelMessages()) { message in
                                    ThreadedMessageView(
                                        message: message,
                                        conversation: conversation,
                                        isExpanded: expandedThreads.contains(message.id),
                                        onReply: { messageID in
                                            replyingToMessageID = messageID
                                        },
                                        onToggleThread: { messageID in
                                            withAnimation {
                                                if expandedThreads.contains(messageID) {
                                                    expandedThreads.remove(messageID)
                                                } else {
                                                    expandedThreads.insert(messageID)
                                                }
                                            }
                                        },
                                        onRun: { code, libraryId in
                                            onRunCode?(code, libraryId)
                                        },
                                        onToggleFavorite: { enhancedMessage in
                                            // Convert EnhancedChatMessage to ChatMessage for toggleFavorite
                                            let chatMessage = ChatMessage(
                                                id: enhancedMessage.id.uuidString,
                                                content: enhancedMessage.content,
                                                isUser: enhancedMessage.isUser,
                                                timestamp: enhancedMessage.timestamp,
                                                libraryId: enhancedMessage.libraryId
                                            )
                                            toggleFavorite(for: chatMessage)
                                        },
                                        isFavorited: { messageId in
                                            return favoritedMessageIds.contains(messageId)
                                        }
                                    )
                                    .id(message.id)
                                }
                            } else {
                                // Legacy message view for current session
                                ForEach(viewModel.messages) { message in
                                    legacyMessageView(message)
                                        .id(message.id)
                                }
                            }

                            if viewModel.isLoading {
                                loadingIndicator
                            }
                        }
                        .padding()
                        .frame(maxWidth: maxMessageWidth)
                        .frame(maxWidth: .infinity) // Center the content
                    }
                    // The chat style's backdrop; it follows the app's light or dark appearance.
                    .background(ChatBackdrop(theme: theme).ignoresSafeArea(edges: .horizontal))
                    .fontDesign(theme.monospaced ? .monospaced : .default)
                    .onChange(of: viewModel.streamingReply.count / 200) { _ in
                        // Keep the live reply in view as it grows.
                        proxy.scrollTo("live-reply", anchor: .bottom)
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }

                            // Auto-save conversation only after AI responses (not user messages)
                            if currentConversation == nil && !lastMessage.isUser && !viewModel.messages.isEmpty {
                                autoSaveConversation()
                            }
                        }
                    }
                }

                // Bottom input section (reply indicator + input area)
                VStack(spacing: 0) {
                    // Reply indicator
                    if let replyID = replyingToMessageID {
                        replyIndicatorView(for: replyID)
                    }

                    // Input area
                    inputAreaView
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                switch DebugLaunch.screen {
                case "history": showHistory = true
                case "favorites": showFavorites = true
                default: break
                }
            }
            .sheet(isPresented: $showHistory) {
                ConversationHistoryView(
                    storageManager: storageManager,
                    isPresented: $showHistory,
                    selectedConversation: $selectedHistoryConversation
                )
            }
            .sheet(isPresented: $showFavorites) {
                FavoritesView(
                    storageManager: storageManager,
                    isPresented: $showFavorites,
                    selectedFavorite: $selectedFavorite
                )
            }
            .onChange(of: selectedHistoryConversation) { newConversation in
                if let conversation = newConversation {
                    loadConversation(conversation)
                    selectedHistoryConversation = nil
                }
            }
            .onChange(of: selectedFavorite) { newFavorite in
                if let favorite = newFavorite {
                    loadAndRunFavorite(favorite)
                    selectedFavorite = nil
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        // Missing key: ask for it here, then send the draft or retry the failed message.
        .sheet(item: $viewModel.keyPrompt) { prompt in
            APIKeyEntrySheet(
                provider: prompt.provider,
                onSave: { key in
                    viewModel.setAPIKey(for: prompt.provider, key: key)
                    viewModel.keyPrompt = nil
                    if viewModel.retryAfterKey {
                        viewModel.retryAfterKey = false
                        viewModel.retryLastUserMessage()
                    } else if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sendMessage()
                    }
                },
                onCancel: {
                    viewModel.keyPrompt = nil
                    viewModel.retryAfterKey = false
                }
            )
        }
        .onAppear {
            loadFavoritedMessageIds()
            restoreCurrentConversationIfNeeded()
        }
    }

    // MARK: - Subviews

    // MARK: - Model and Library Header (broken into sub-views for compiler)

    /// The single top bar: navigation, model and library pickers, and actions
    /// in one row, so the conversation gets the rest of the screen. The
    /// wordmark sits in the true centre when there is room for it (iPad); on
    /// a phone it is left out and documentation moves into the menu.
    private var modelAndLibraryHeader: some View {
        VStack(spacing: 0) {
            ZStack {
                if horizontalSizeClass == .regular {
                    HStack(spacing: 8) {
                        MaigeXRAvatar(size: 24)
                        MaigeXRBrandText(isActive: true, fontSize: 17)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }

                HStack(spacing: 8) {
                    Button(action: { showHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .buttonStyle(CompactIconButtonStyle(tint: .brandAccentText))
                    .accessibilityLabel("History")

                    modelSelectorView
                    librarySelectorView

                    Spacer(minLength: 8)

                    if horizontalSizeClass == .regular {
                        Button(action: openLibraryDocs) {
                            Image(systemName: "book")
                        }
                        .buttonStyle(CompactIconButtonStyle(tint: .brandAccentText))
                        .accessibilityLabel("\(viewModel.libraryManager.selectedLibrary.displayName) documentation")
                    }

                    Button(action: { showFavorites = true }) {
                        Image(systemName: "star")
                    }
                    .buttonStyle(CompactIconButtonStyle(tint: .brandAccentText))
                    .accessibilityLabel("Favorites")

                    moreMenu
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 52)

            Hairline()
        }
        .background(Color.brandBackground)
    }

    private func openLibraryDocs() {
        if let url = URL(string: viewModel.libraryManager.selectedLibrary.documentationURL) {
            UIApplication.shared.open(url)
        }
    }

    private var moreMenu: some View {
        Menu {
            if horizontalSizeClass != .regular {
                Button(action: openLibraryDocs) {
                    Label("\(viewModel.libraryManager.selectedLibrary.displayName) Docs", systemImage: "book")
                }
            }

            Button {
                isCompactView.toggle()
            } label: {
                Label(isCompactView ? "Wide View" : "Compact View",
                      systemImage: isCompactView ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
            }

            Button {
                saveCurrentConversation()
            } label: {
                Label("Save Conversation", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.messages.isEmpty)

            Button(role: .destructive) {
                clearCurrentConversation()
            } label: {
                Label("New Conversation", systemImage: "plus.bubble")
            }
        } label: {
            // Menu labels ignore button styles, so match CompactIconButtonStyle by hand.
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.brandAccentText)
                .frame(width: Metrics.control, height: Metrics.control)
                .background(Circle().fill(Color.brandSurface.opacity(0.7)))
                .contentShape(Circle())
        }
        .accessibilityLabel("More")
    }

    private var modelSelectorView: some View {
        modelMenuView
            .accessibilityLabel("Model: \(viewModel.getModelDisplayName(viewModel.selectedModel))")
    }

    private var modelMenuView: some View {
        Menu {
            modelMenuContent
        } label: {
            modelMenuLabel
        }
    }

    private var modelMenuContent: some View {
        Group {
            ForEach(Array(viewModel.modelsByProvider.keys.sorted()), id: \.self) { provider in
                Section(provider) {
                    ForEach(viewModel.modelsByProvider[provider] ?? [], id: \.id) { model in
                        Button(action: {
                            viewModel.selectModel(model.id)
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.displayName)
                                        .font(.system(size: 14, weight: .medium))
                                    Text("\(model.description) - \(model.pricing)")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if viewModel.selectedModel == model.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }

            if !viewModel.availableModels.isEmpty {
                Section("Legacy") {
                    ForEach(viewModel.availableModels, id: \.self) { model in
                        Button(action: {
                            viewModel.selectedModel = model
                        }) {
                            HStack {
                                Text(viewModel.getModelDisplayName(model))
                                    .font(.system(size: 14, weight: .medium))
                                if viewModel.selectedModel == model {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var modelMenuLabel: some View {
        PillLabel(icon: "cpu", text: viewModel.getModelDisplayName(viewModel.selectedModel),
                  maxTextWidth: horizontalSizeClass == .regular ? 140 : 84)
    }

    private var librarySelectorView: some View {
        libraryMenuView
            .accessibilityLabel("Library: \(viewModel.libraryManager.selectedLibrary.displayName)")
    }

    private var libraryMenuView: some View {
        Menu {
            ForEach(viewModel.libraryManager.availableLibraries, id: \.id) { library in
                Button(action: {
                    viewModel.selectLibrary(id: library.id)
                }) {
                    HStack {
                        Text(library.displayName)
                            .font(.system(size: 14, weight: .medium))
                        if viewModel.libraryManager.selectedLibrary.id == library.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                    }
                }
            }
        } label: {
            libraryMenuLabel
        }
    }

    private var libraryMenuLabel: some View {
        PillLabel(icon: "cube", text: viewModel.libraryManager.selectedLibrary.displayName,
                  maxTextWidth: horizontalSizeClass == .regular ? 140 : 72)
    }

    private func conversationHeaderView(_ conversation: Conversation) -> some View {
        VStack(spacing: 4) {
            Text(conversation.title)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 8) {
                if let library = conversation.library3DID {
                    Text(library)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }

                if let model = conversation.modelUsed {
                    Text(model)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(relativeDateString(from: conversation.updatedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(Color(.systemGray6))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }

    private func legacyMessageView(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    // Solid accent fill, not a glass panel. glassCard tints with
                    // the surface tone, which is pale in light mode, and the
                    // bubble's text is white — so the sent message was white on
                    // near-white and effectively unreadable.
                    MarkdownMessageView(content: message.content, isUser: true)
                        .padding(12)
                        .frame(maxWidth: 600, alignment: .leading)
                        .chatBubble(theme, isUser: true)

                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    MarkdownMessageView(content: message.content, isUser: false)
                        .padding(12)
                        .frame(maxWidth: 600, alignment: .leading)
                        .chatBubble(theme, isUser: false)

                    // Timestamp and action buttons
                    HStack(spacing: 12) {
                        Text(formatTime(message.timestamp))
                            .font(.caption2)
                            .foregroundColor(.gray)

                        // Reply button (always show when there are messages - threading works for all conversations)
                        // Check if we have any saved conversations OR if current conversation exists
                        if !viewModel.messages.isEmpty && viewModel.messages.count > 1 {
                            Button(action: {
                                // Convert String ID to UUID for reply functionality
                                if let messageUUID = UUID(uuidString: message.id) {
                                    replyingToMessageID = messageUUID

                                    // Ensure conversation is created/updated for threading
                                    if currentConversation == nil {
                                        // Auto-create conversation if it doesn't exist
                                        let enhancedMessages = viewModel.messages.map { EnhancedChatMessage(from: $0) }
                                        let firstUserMessage = viewModel.messages.first(where: { $0.isUser })
                                        let title = generateConversationTitle(from: firstUserMessage?.content ?? "New Conversation")

                                        var newConversation = Conversation(
                                            title: title,
                                            messages: enhancedMessages,
                                            library3DID: viewModel.libraryManager.selectedLibrary.id,
                                            modelUsed: viewModel.selectedModel
                                        )

                                        storageManager.addConversation(newConversation)
                                        currentConversation = newConversation
                                    } else {
                                        // Update existing conversation with latest messages
                                        var updated = currentConversation!
                                        updated.messages = viewModel.messages.map { EnhancedChatMessage(from: $0) }
                                        currentConversation = updated
                                        storageManager.updateConversation(updated)
                                    }
                                }
                            }) {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // ALWAYS show "Run the Scene" button for AI messages
                        RunSceneButton(
                            message: message,
                            onRunCode: onRunCode
                        )

                        // Star/Favorite button for AI code messages
                        if Self.extractCode(from: message.content) != nil {
                            Button(action: {
                                toggleFavorite(for: message)
                            }) {
                                Image(systemName: isFavorited(message.id) ? "star.fill" : "star")
                                    .font(.caption)
                                    .foregroundColor(isFavorited(message.id) ? .brandAccentText : .brandMuted)
                            }
                        }
                    }
                    .frame(maxWidth: 600, alignment: .leading)
                }
                Spacer()
            }
        }
    }

    static func extractCode(from content: String) -> String? {
        // Extract code from markdown code blocks
        // Reduced logging to prevent spam on every render

        // STRICT: Only extract code from TRIPLE backtick blocks (``` not `)
        // Find the start of the code block
        let possibleStarts = ["```javascript", "```typescript", "```js", "```ts", "```jsx", "```html", "```"]
        var codeStart: String.Index? = nil
        var foundMarker = ""

        for marker in possibleStarts {
            if let range = content.range(of: marker) {
                // Verify it's actually triple backticks, not more
                let beforeMarker = content[..<range.lowerBound]
                let afterMarkerStart = content.index(range.upperBound, offsetBy: 0, limitedBy: content.endIndex) ?? content.endIndex
                
                // Make sure we're not matching part of a longer backtick sequence
                if !beforeMarker.hasSuffix("`") &&
                   (afterMarkerStart == content.endIndex || !content[afterMarkerStart...].hasPrefix("`")) {
                    codeStart = range.upperBound
                    foundMarker = marker
                    break
                }
            }
        }

        guard let start = codeStart else {
            return nil
        }

        // Find the end of the code block (closing triple backticks)
        let afterStart = content[start...]

        // Look for newline followed by ``` (the proper closing)
        guard let endRange = afterStart.range(of: "\n```") ?? afterStart.range(of: "```") else {
            return nil
        }

        // Extract the code between start and end
        let codeRange = start..<endRange.lowerBound
        var code = String(content[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove any artifacts that might be at the end
        let artifactsToRemove = ["[/INSERT_CODE]", "[RUN_SCENE]", "```"]
        for artifact in artifactsToRemove {
            if code.hasSuffix(artifact) {
                code = String(code.dropLast(artifact.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Sanity check: ignore if it's too short (probably not real code)
        if code.count < 10 {
            print("⚠️ Extracted code too short, ignoring")
            return nil
        }
        
        return code.isEmpty ? nil : code
    }

    /// The reply as it arrives: live text once the model starts answering,
    /// "Thinking…" before that.
    private var loadingIndicator: some View {
        // One bubble: the status line inside it, the text below once it starts.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.neonCyan)
                Text(viewModel.streamingReply.isEmpty || viewModel.isThinking ? "Thinking..." : "Writing...")
                    .font(.callout)
                    .foregroundColor(.neonCyan)
            }
            .accessibilityElement(children: .combine)
            if !viewModel.streamingReply.isEmpty {
                MarkdownMessageView(content: viewModel.streamingReply, isUser: false)
            }
        }
        .padding(12)
        .frame(maxWidth: 600, alignment: .leading)
        .chatBubble(theme, isUser: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .id("live-reply")
    }

    private func replyIndicatorView(for messageID: UUID) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let message = currentConversation?.messages.first(where: { $0.id == messageID }) {
                    Text(String(message.content.prefix(50)) + (message.content.count > 50 ? "..." : ""))
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: { replyingToMessageID = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator)),
            alignment: .top
        )
    }

    private var inputAreaView: some View {
        VStack(spacing: 0) {
            // Image preview area
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedImages.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                // Remove button
                                Button(action: {
                                    selectedImages.remove(at: index)
                                    selectedPhotos.remove(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                }
                                .padding(4)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemGray5))
            }

            Hairline()

            // Input row: attach on the left, then one rounded field with the send
            // button inside it, the way Messages lays it out.
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 5, matching: .images) {
                    Image(systemName: selectedImages.isEmpty ? "photo.on.rectangle" : "photo.on.rectangle.fill")
                }
                .buttonStyle(CompactIconButtonStyle(tint: selectedImages.isEmpty ? .brandMuted : .brandAccentText))
                .accessibilityLabel("Attach images")
                .padding(.bottom, 4)
                .onChange(of: selectedPhotos) { newItems in
                    Task {
                        await loadSelectedImages(from: newItems)
                    }
                }

                HStack(alignment: .bottom, spacing: 6) {
                    TextField("Describe a scene…", text: $inputText, axis: .vertical)
                        .font(.body)
                        .submitLabel(.send)
                        .onSubmit {
                            sendMessage()
                        }
                        .lineLimit(1...5)
                        .padding(.vertical, 9)

                    let canSend = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isLoading
                    Group {
                    if viewModel.isLoading {
                        // While a reply is coming, the button stops it.
                        Button(action: { viewModel.stopReply() }) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: Metrics.control, height: Metrics.control)
                                .background(Circle().fill(Color.brandAccent))
                        }
                        .accessibilityLabel("Stop reply")
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: Metrics.control, height: Metrics.control)
                                .background(Circle().fill(canSend ? Color.brandAccent : Color.brandMuted.opacity(0.35)))
                        }
                        .disabled(!canSend)
                        .accessibilityLabel("Send")
                    }
                    }
                    .padding(.bottom, 4)
                }
                .padding(.leading, 14)
                .padding(.trailing, 4)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.brandSurface))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.brandBackground)
        }
    }

    private var navigationTitle: String {
        if let conversation = currentConversation {
            return conversation.title
        } else {
            return "m{ai}geXR"
        }
    }

    // MARK: - Helper Functions

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // No key for this model's provider yet: ask for it now and keep the draft,
        // instead of sending and answering with an error.
        if let provider = viewModel.providerMissingKey(for: viewModel.selectedModel) {
            viewModel.keyPrompt = KeyPrompt(provider: provider)
            return
        }

        let messageContent = inputText
        let imagesCopy = selectedImages

        // Clear input and images
        inputText = ""
        selectedImages = []
        selectedPhotos = []

        // Dismiss keyboard immediately after sending
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        if let conversation = currentConversation {
            // Add message as threaded reply
            var updatedConversation = conversation
            let displayContent = !imagesCopy.isEmpty ?
                (imagesCopy.count == 1 ? "\(messageContent) [📷 1 image]" : "\(messageContent) [📷 \(imagesCopy.count) images]") :
                messageContent

            // Capture parent ID before clearing
            let parentID = replyingToMessageID

            let newMessage = EnhancedChatMessage(
                content: displayContent,
                isUser: true,
                threadParentID: parentID
            )
            updatedConversation.messages.append(newMessage)

            // Update parent's replies array
            if let parentID = parentID,
               let parentIndex = updatedConversation.messages.firstIndex(where: { $0.id == parentID }) {
                updatedConversation.messages[parentIndex].replies.append(newMessage.id)
            }

            currentConversation = updatedConversation
            storageManager.updateConversation(updatedConversation)

            // Get parent message BEFORE clearing replyingToMessageID
            let parentMessage = parentID != nil ?
                updatedConversation.messages.first(where: { $0.id == parentID }) : nil

            // Clear reply state
            replyingToMessageID = nil

            // Send to AI and get response with parent context if this is a reply
            Task {
                await sendToAIAndUpdateConversation(
                    messageContent,
                    images: imagesCopy,
                    in: updatedConversation,
                    replyingTo: parentMessage
                )
            }
        } else {
            // Legacy path - send through existing ViewModel
            if !imagesCopy.isEmpty {
                viewModel.sendMessageWithImages(messageContent, images: imagesCopy)
            } else {
                viewModel.sendMessage(messageContent)
            }
        }
    }

    private func loadSelectedImages(from items: [PhotosPickerItem]) async {
        var loadedImages: [UIImage] = []

        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loadedImages.append(image)
            }
        }

        await MainActor.run {
            self.selectedImages = loadedImages
        }
    }

    private func sendToAIAndUpdateConversation(_ userMessage: String, images: [UIImage] = [], in conversation: Conversation, replyingTo parentMessage: EnhancedChatMessage? = nil) async {
        // Sync conversation to viewModel to get AI response
        // The user message is already in the conversation, so we just sync all messages
        await MainActor.run {
            // Convert all conversation messages (including the new user message) to viewModel format
            viewModel.messages = conversation.messages.map { enhanced in
                ChatMessage(
                    id: enhanced.id.uuidString,
                    content: enhanced.content,
                    isUser: enhanced.isUser,
                    timestamp: enhanced.timestamp,
                    libraryId: enhanced.libraryId
                )
            }
        }

        // Build enhanced message with parent context if replying
        var enhancedUserMessage = userMessage

        if let parent = parentMessage {
            // Extract code from parent message if it exists
            let parentCode = EnhancedChatView.extractCode(from: parent.content)

            // Build context-aware message
            var contextMessage = "I'm replying to your previous message"

            if !parent.isUser {
                contextMessage += " where you provided"
                if let code = parentCode {
                    contextMessage += " the following code:\n\n```\n\(code)\n```\n\n"
                } else {
                    contextMessage += ":\n\n> \(String(parent.content.prefix(300)))\(parent.content.count > 300 ? "..." : "")\n\n"
                }
            }

            contextMessage += "My request: \(userMessage)"
            enhancedUserMessage = contextMessage

            print("🔄 Enhanced reply with parent context:")
            print("📝 Parent had code: \(parentCode != nil)")
            print("📝 Enhanced message length: \(enhancedUserMessage.count)")
        }

        // Use viewModel's sendMessage which handles AI response
        await MainActor.run {
            if !images.isEmpty {
                viewModel.sendMessageWithImages(enhancedUserMessage, images: images)
            } else {
                viewModel.sendMessage(enhancedUserMessage)
            }
        }

        // Wait for the response and sync back to conversation
        Task { @MainActor in
            // Wait for loading to finish
            while viewModel.isLoading {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }

            // Sync viewModel messages back to conversation
            guard var updatedConversation = currentConversation else { return }

            // Update conversation with all messages from viewModel
            updatedConversation.messages = viewModel.messages.map { EnhancedChatMessage(from: $0) }
            updatedConversation.updatedAt = Date()

            currentConversation = updatedConversation
            storageManager.updateConversation(updatedConversation)

            // Clear viewModel messages to avoid confusion
            viewModel.messages.removeAll()
        }
    }

    private func saveCurrentConversation() {
        guard !viewModel.messages.isEmpty else { return }

        let enhancedMessages = viewModel.messages.map { EnhancedChatMessage(from: $0) }
        var newConversation = Conversation(
            title: "New Conversation",
            messages: enhancedMessages,
            library3DID: viewModel.libraryManager.selectedLibrary.id,
            modelUsed: viewModel.selectedModel
        )
        newConversation.generateTitleIfNeeded()

        storageManager.addConversation(newConversation)
        currentConversation = newConversation
    }

    private func autoSaveConversation() {
        // Automatically save conversation after AI responses
        guard !viewModel.messages.isEmpty else { return }

        if let conversation = currentConversation {
            // Update existing conversation with new messages
            var updatedConversation = conversation
            let enhancedMessages = viewModel.messages.map { EnhancedChatMessage(from: $0) }
            updatedConversation.messages = enhancedMessages
            updatedConversation.updatedAt = Date()

            storageManager.updateConversation(updatedConversation)
            currentConversation = updatedConversation
        } else {
            // Create new conversation with title from first user message
            let enhancedMessages = viewModel.messages.map { EnhancedChatMessage(from: $0) }

            // Find the first user message to use as the title
            let firstUserMessage = viewModel.messages.first(where: { $0.isUser })
            let title = generateConversationTitle(from: firstUserMessage?.content ?? "New Conversation")

            let newConversation = Conversation(
                title: title,
                messages: enhancedMessages,
                library3DID: viewModel.libraryManager.selectedLibrary.id,
                modelUsed: viewModel.selectedModel
            )

            storageManager.addConversation(newConversation)
            currentConversation = newConversation
        }
    }

    private func generateConversationTitle(from message: String) -> String {
        // Clean and truncate the message to create a good title
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // Take first line or first 50 characters
        let firstLine = cleaned.components(separatedBy: .newlines).first ?? cleaned
        if firstLine.count <= 50 {
            return firstLine
        } else {
            return String(firstLine.prefix(47)) + "..."
        }
    }

    private func loadConversation(_ conversation: Conversation) {
        currentConversation = conversation
        expandedThreads.removeAll()
        replyingToMessageID = nil

        // Clear current session
        viewModel.messages.removeAll()
    }

    private func clearCurrentConversation() {
        if currentConversation != nil {
            saveCurrentConversation()
        }

        currentConversation = nil
        expandedThreads.removeAll()
        replyingToMessageID = nil
        viewModel.messages.removeAll()
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Favorites

    private func loadAndRunFavorite(_ favorite: Favorite) {
        // Set the 3D library if specified
        if let libraryId = favorite.libraryId {
            viewModel.libraryManager.selectLibrary(id: libraryId)
        }

        // Run the code automatically
        onRunCode?(favorite.codeContent, favorite.libraryId)

        print("▶️ Running favorite: \(favorite.title)")
    }

    private func isFavorited(_ messageId: String) -> Bool {
        guard let uuid = UUID(uuidString: messageId) else { return false }
        return favoritedMessageIds.contains(uuid)
    }

    private func toggleFavorite(for message: ChatMessage) {
        Task {
            do {
                // Convert String ID to UUID
                guard let messageUUID = UUID(uuidString: message.id) else {
                    print("❌ Invalid message ID format: \(message.id)")
                    return
                }

                // Check if already favorited
                if let existing = try await storageManager.getFavoriteByMessageId(messageId: messageUUID) {
                    // Remove favorite
                    try await storageManager.deleteFavorite(id: existing.id)
                    await MainActor.run {
                        favoritedMessageIds.remove(messageUUID)
                    }
                    print("⭐ Removed favorite: \(existing.title)")
                } else {
                    // Add favorite
                    guard let code = Self.extractCode(from: message.content) else {
                        print("⚠️ No code found in message to favorite")
                        return
                    }

                    let title = SceneText.title(fromReply: message.content) ?? generateFavoriteTitle(from: code)
                    let conversationId = currentConversation?.id ?? UUID()

                    try await storageManager.saveFavorite(
                        messageId: messageUUID,
                        conversationId: conversationId,
                        title: title,
                        codeContent: code,
                        libraryId: viewModel.getCurrentLibrary().id,
                        modelUsed: viewModel.selectedModel,
                        screenshotBase64: currentConversation?.screenshotBase64
                    )

                    await MainActor.run {
                        favoritedMessageIds.insert(messageUUID)
                    }
                    print("⭐ Added favorite: \(title)")
                }
            } catch {
                print("❌ Error toggling favorite: \(error)")
            }
        }
    }

    private func generateFavoriteTitle(from code: String) -> String {
        // Extract first meaningful line or use code structure
        let lines = code.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("/*") }

        if let firstLine = lines.first {
            return String(firstLine.prefix(50))
        }
        return "Untitled Scene"
    }

    private func loadFavoritedMessageIds() {
        Task {
            do {
                let favorites = try await storageManager.loadFavorites()
                await MainActor.run {
                    favoritedMessageIds = Set(favorites.map { $0.messageId })
                }
                print("📋 Loaded \(favorites.count) favorited message IDs")
            } catch {
                print("❌ Error loading favorited IDs: \(error)")
            }
        }
    }

    private func restoreCurrentConversationIfNeeded() {
        // If we have messages but no current conversation, try to restore from storage
        // This handles the case where the view was recreated after switching to Scene tab
        guard currentConversation == nil && !viewModel.messages.isEmpty else {
            return
        }

        print("🔄 Restoring current conversation after view recreation...")

        // Check if the most recent conversation matches our current messages
        if let latestConversation = storageManager.conversations.first {
            // Compare message count as a simple heuristic
            if latestConversation.messages.count == viewModel.messages.count {
                print("✅ Restored conversation: \(latestConversation.title)")
                currentConversation = latestConversation
            }
        }
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @StateObject var viewModel = ChatViewModel()
        @StateObject var storageManager = ConversationStorageManager()

        var body: some View {
            EnhancedChatView(
                viewModel: viewModel,
                storageManager: storageManager
            )
        }
    }

    return PreviewWrapper()
}

// MARK: - Run Scene Button Component
// Separate component to properly cache code extraction and avoid re-rendering issues
struct RunSceneButton: View {
    let message: ChatMessage
    let onRunCode: ((String, String?) -> Void)?

    // Cache the extracted code using @State to prevent re-extraction on every render
    @State private var extractedCode: String?
    @State private var isInitialized = false

    var body: some View {
        Button(action: {
            // Try to extract code first, fallback to full content if no code blocks found
            if let code = extractedCode {
                print("🎯 Running extracted code (\(code.count) chars) with library: \(message.libraryId ?? "current")")
                onRunCode?(code, message.libraryId)
            } else {
                print("⚠️ No code blocks found, running full message content with library: \(message.libraryId ?? "current")")
                onRunCode?(message.content, message.libraryId)
            }
        }) {
            RunSceneLabel(hasCode: extractedCode != nil)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if !isInitialized {
                extractedCode = EnhancedChatView.extractCode(from: message.content)
                isInitialized = true
            }
        }
    }
}
