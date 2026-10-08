import Foundation
import LlamaStackClient
import AIProxy
import Combine
import UIKit

enum APIError: Error {
    case emptyResponse
    case tooManyRetries
    case invalidModel
}

// MARK: - Configuration Constants
internal let DEFAULT_API_KEY = "changeMe"

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedModel: String = "zai-org/GLM-5.3-Flash"
    @Published var temperature: Double = 0.7
    @Published var topP: Double = 0.9
    /// Reasoning depth for models that use effort instead of temperature/top-p.
    @Published var effort: AIEffort = .high

    /// How the app picks light or dark. Mirrors the desktop client's setting.
    ///
    /// Backed by AppearanceStore, which the root scene observes, so moving the
    /// picker changes the theme immediately rather than on Save.
    var appearance: AppAppearance {
        get { AppearanceStore.shared.appearance }
        set { AppearanceStore.shared.appearance = newValue }
    }
    @Published var apiKey: String = DEFAULT_API_KEY // Legacy - for backwards compatibility
    @Published var systemPrompt: String = ""
    
    // New AI Provider System
    private(set) var aiProviderManager = AIProviderManager()

    /// Provider behind the selected model, so error messages can name it.
    var currentProviderDisplayName: String {
        aiProviderManager.getProvider(for: selectedModel)?.name ?? "The AI provider"
    }

    // 3D Library Management System
    let library3DManager = Library3DManager()

    // Published property to trigger UI updates when library changes
    @Published var currentLibraryId: String = "babylonjs"
    
    // Build System Management
    private let buildManager = BuildManager.shared
    
    // Expose managers for UI and tests
    var providerManager: AIProviderManager {
        return aiProviderManager
    }
    
    var libraryManager: Library3DManager {
        return library3DManager
    }
    
    var buildSystem: BuildManager {
        return buildManager
    }

    // RAG Services (Retrieval-Augmented Generation)
    internal var embeddingService: EmbeddingService?
    internal var vectorSearchService: VectorSearchService?
    internal var ragContextBuilder: RAGContextBuilder?
    @Published var ragEnabled: Bool = false

    // Legacy providers - maintained for compatibility
    private var inference: RemoteInference
    private var togetherAIService: TogetherAIService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Configuration Toggle
    /// Controls routing for Llama models:
    /// - `true`: Use local LlamaStack server for meta-llama models (supports max_tokens via server config)
    /// - `false`: Use Together.ai for ALL models (supports max_tokens via API, prevents truncation)
    /// 
    /// **Current Setting: false** = All models use Together.ai (recommended for reliability)
    /// 
    /// To switch back to LlamaStack for Llama models:
    /// 1. Change this to `true`
    /// 2. Ensure LlamaStack server is running on localhost:8321
    /// 3. Configure server with higher token limits if needed
    private let useLlamaStackForLlamaModels: Bool = false
    
    // MARK: - Optimization Configuration
    /// API call optimization settings to prevent multiple redundant calls
    /// 
    /// **BEFORE OPTIMIZATION**: Up to 10 API calls per user message
    /// - Initial call: 1
    /// - Retry attempts: 3
    /// - Validation retries: 3  
    /// - Error retries: 3
    /// **Total**: 1 + 3 + 3 + 3 = 10 calls
    /// 
    /// **AFTER OPTIMIZATION**: Maximum 2 API calls per user message
    /// - Initial call: 1
    /// - Retry attempts: 1 (only for empty/severely truncated responses or network errors)
    /// **Total**: 1 + 1 = 2 calls
    private let maxRetryAttempts: Int = 1
    private let minimumResponseLength: Int = 50 // Chars below this trigger retry
    
    // Available models (ordered by cost - cheapest first) - Legacy, now using aiProviderManager.getAllModels()
    // NOTE: Only serverless models are included. Non-serverless models require dedicated endpoints.
    let availableModels = [
        "deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free", // FREE - DeepSeek R1 reasoning model
        "meta-llama/Llama-3.3-70B-Instruct-Turbo-Free", // FREE - Latest Llama 3.3 70B
        "meta-llama/Meta-Llama-3-8B-Instruct-Lite",     // $0.10/1M - CHEAPEST paid
        "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo",  // $0.18/1M - Good balance
        "Qwen/Qwen2.5-7B-Instruct-Turbo"                // $0.30/1M - Fastest Qwen
    ]
    
    // MARK: - New Provider System Properties
    var allAvailableModels: [AIModel] {
        return aiProviderManager.getAllModels()
    }
    
    var modelsByProvider: [String: [AIModel]] {
        return aiProviderManager.getModelsByProvider()
    }
    
    var currentProvider: AIProvider? {
        return aiProviderManager.currentProvider
    }
    
    // Callbacks for WebView interaction
    var onInsertCode: ((String) -> Void)?
    var onRunScene: (() -> Void)?
    var onDescribeScene: ((String) -> Void)?
    
    // Enhanced callbacks for build system
    var onInsertCodeWithBuild: ((String, FrameworkKind) -> Void)?

    /// A request cut off by the app going to the background, sent again on return.
    let interruptedRequests = InterruptedRequestQueue()
    private var becameActiveObserver: NSObjectProtocol?
    private var lifecycleObservers: [NSObjectProtocol] = []

    init() {
        print("🚀 ChatViewModel initialization starting...")


        // Initialize LlamaStackClient for meta-llama models
        self.inference = RemoteInference(
            url: URL(string: "https://llama-stack.together.ai")!,
            apiKey: DEFAULT_API_KEY
        )

        // Initialize AIProxy for Together.ai (Qwen/DeepSeek models)
        self.togetherAIService = AIProxy.togetherAIDirectService(
            unprotectedAPIKey: DEFAULT_API_KEY
        )

        print("📚 Setting up library manager and AI providers...")

        // Initialize currentLibraryId from library3DManager
        self.currentLibraryId = library3DManager.selectedLibrary.id

        // Observe library changes and sync currentLibraryId
        library3DManager.$selectedLibrary
            .sink { [weak self] newLibrary in
                guard let self = self else { return }
                print("📢 Library3DManager selectedLibrary changed to: \(newLibrary.displayName)")
                self.currentLibraryId = newLibrary.id
                print("✅ Updated currentLibraryId to: \(self.currentLibraryId)")
            }
            .store(in: &cancellables)

        setupInitialMessage()
        setupDefaultSystemPrompt()
        loadSettings()

        print("✅ ChatViewModel initialization complete")
        print("🔑 Current Together.ai API key status: \(aiProviderManager.getAPIKey(for: "Together.ai") == "changeMe" ? "NOT_CONFIGURED" : "CONFIGURED")")

        // Send a request cut off in the background again when the app is back.
        becameActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.interruptedRequests.resume()
                self?.checkReplyOnReturn()
            }
        }
        // Leaving the app mid-reply: let the background session finish it.
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handOffActiveReplyToBackground() }
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: BackgroundReplyService.finishedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let jobID = note.userInfo?["jobID"] as? String else { return }
            Task { @MainActor in self?.collectBackgroundReply(jobID: jobID) }
        })
        collectOrphanedReplies()
    }
    
    private func setupInitialMessage() {
        var welcomeContent = library3DManager.getWelcomeMessage()
        
        // Check if API key is configured
        let currentAPIKey = aiProviderManager.getAPIKey(for: "Together.ai")
        if currentAPIKey == "changeMe" {
            welcomeContent += "\n\n⚠️ **Setup Required**: Please configure your Together.ai API key in Settings (gear icon) to start chatting. Get your free API key at https://api.together.ai/settings/api-keys"
        }
        
        let welcomeMessage = ChatMessage(
            id: UUID().uuidString,
            content: welcomeContent,
            isUser: false,
            timestamp: Date(),
            libraryId: library3DManager.selectedLibrary.id
        )
        messages.append(welcomeMessage)
    }
    
    private func setupDefaultSystemPrompt() {
        // Use the selected library's system prompt as the default
        systemPrompt = library3DManager.getSystemPrompt()
    }
    
    func updateAPIKey(_ newKey: String) {
        apiKey = newKey
        // Reinitialize both legacy services with new API key
        togetherAIService = AIProxy.togetherAIDirectService(
            unprotectedAPIKey: apiKey
        )
        // Reinitialize LlamaStackClient inference with new API key
        inference = RemoteInference(
            url: URL(string: "https://llama-stack.together.ai")!,
            apiKey: apiKey
        )
        
        // Also update Together.ai provider in the new system (backwards compatibility)
        aiProviderManager.setAPIKey(for: "Together.ai", key: newKey)
    }
    
    // MARK: - New Provider System Methods
    
    func setAPIKey(for provider: String, key: String) {
        aiProviderManager.setAPIKey(for: provider, key: key)
        
        // Keep legacy apiKey in sync for Together.ai
        if provider == "Together.ai" {
            apiKey = key
        }
    }
    
    // MARK: - 3D Library System Methods
    
    /// React Three Fiber and Reactylon need an npm build, so their scenes always
    /// run on CodeSandbox; there is no offline playground for them.
    static func requiresCodeSandbox(_ libraryId: String) -> Bool {
        libraryId == "reactThreeFiber" || libraryId == "reactylon"
    }

    /// Shown once when switching to a framework that runs on CodeSandbox.
    @Published var codeSandboxNotice: String?

    func selectLibrary(id: String) {
        if Self.requiresCodeSandbox(id) && id != currentLibraryId {
            let name = id == "reactylon" ? "Reactylon" : "React Three Fiber"
            codeSandboxNotice = "\(name) scenes are built and run on CodeSandbox (codesandbox.io), so they need an internet connection."
        }
        // Update published property FIRST to trigger UI refresh immediately
        currentLibraryId = id

        library3DManager.selectLibrary(id: id)

        // Update the welcome message and system prompt when library changes
        setupDefaultSystemPrompt()

        // Update the welcome message
        if !messages.isEmpty {
            messages[0] = ChatMessage(
                id: messages[0].id,
                content: library3DManager.getWelcomeMessage(),
                isUser: false,
                timestamp: messages[0].timestamp,
                libraryId: library3DManager.selectedLibrary.id
            )
        }

        print("🎯 Switched to \(library3DManager.selectedLibrary.displayName)")
        print("📊 currentLibraryId is now: \(currentLibraryId)")
    }
    
    func selectLibrary(_ library: any Library3D) {
        // Update published property FIRST to trigger UI refresh immediately
        currentLibraryId = library.id

        library3DManager.selectLibrary(library)

        // Update the welcome message and system prompt when library changes
        setupDefaultSystemPrompt()

        // Update the welcome message
        if !messages.isEmpty {
            messages[0] = ChatMessage(
                id: messages[0].id,
                content: library3DManager.getWelcomeMessage(),
                isUser: false,
                timestamp: messages[0].timestamp,
                libraryId: library3DManager.selectedLibrary.id
            )
        }

        print("🎯 Switched to \(library3DManager.selectedLibrary.displayName)")
        print("📊 currentLibraryId is now: \(currentLibraryId)")
    }
    
    
    func getCurrentLibrary() -> Library3DManager.AnyLibrary3D {
        return library3DManager.selectedLibrary
    }
    
    func getAvailableLibraries() -> [Library3DManager.AnyLibrary3D] {
        // Filter out Reactylon from the available libraries
        return library3DManager.availableLibraries.filter { $0.id != "reactylon" }
    }
    
    func getDefaultSceneCode() -> String {
        return library3DManager.getDefaultSceneCode()
    }
    
    func getPlaygroundTemplate() -> String {
        return library3DManager.getPlaygroundTemplate()
    }
    
    func getCodeLanguage() -> CodeLanguage {
        return library3DManager.getCodeLanguage()
    }
    
    func getAPIKey(for provider: String) -> String {
        return aiProviderManager.getAPIKey(for: provider)
    }
    
    func getCurrentProvider() -> AIProvider? {
        return aiProviderManager.currentProvider
    }
    
    func setCurrentProvider(_ provider: AIProvider) {
        aiProviderManager.setCurrentProvider(provider)
    }
    
    func isProviderConfigured(_ provider: String) -> Bool {
        return aiProviderManager.isProviderConfigured(provider)
    }
    
    func getConfiguredProviders() -> [AIProvider] {
        return aiProviderManager.getConfiguredProviders()
    }
    
    
    func sendMessage(_ text: String, currentCode: String? = nil) {
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            content: text,
            isUser: true,
            timestamp: Date(),
            libraryId: library3DManager.selectedLibrary.id
        )
        messages.append(userMessage)
        startReply(text: text, currentCode: currentCode)
    }

    // MARK: - Replies that survive leaving the app

    /// The reply in flight. Its id makes sure it is shown exactly once, whether
    /// it arrives by the live stream or from the background session.
    private struct ActiveReply {
        let id: UUID
        let text: String
        let currentCode: String?
        let model: String
        var systemPrompt: String?
        var task: Task<Void, Never>?
        /// Set once the request has been handed to the background session.
        var jobID: String?
        var leftApp = false
        var restarted = false
        /// Last time any text arrived, for spotting a stream that went quiet.
        var lastProgress = Date()
    }

    private var activeReply: ActiveReply?

    /// The reply as it streams in, shown live under the conversation.
    @Published private(set) var streamingReply = ""
    /// True while a reasoning model is still thinking before it answers.
    @Published private(set) var isThinking = false
    private var lastStreamUpdate = Date.distantPast

    private func startReply(text: String, currentCode: String?, restarted: Bool = false) {
        let id = UUID()
        activeReply = ActiveReply(id: id, text: text, currentCode: currentCode, model: selectedModel, restarted: restarted)
        resetStreaming()
        activeReply?.task = Task { [weak self] in
            await self?.processUserMessage(text, currentCode: currentCode, isRetry: restarted, replyID: id)
        }
        monitorStall(id)
    }

    /// Stops the reply in progress (the Stop button).
    func stopReply() {
        guard let reply = activeReply else { return }
        reply.task?.cancel()
        if let jobID = reply.jobID { BackgroundReplyService.shared.cancel(jobID: jobID) }
        activeReply = nil
        resetStreaming()
        isLoading = false
        print("⏹️ Reply stopped by the user")
    }

    private func resetStreaming() {
        streamingReply = ""
        isThinking = false
        lastStreamUpdate = .distantPast
    }

    /// Shows streamed text as it arrives, a few times a second at most.
    private func streamProgress(_ fullText: String, replyID: UUID) {
        guard activeReply?.id == replyID else { return }
        activeReply?.lastProgress = Date()
        guard Date().timeIntervalSince(lastStreamUpdate) > 0.1 else { return }
        lastStreamUpdate = Date()
        let shown = ReplyText.visible(fullText)
        streamingReply = shown.text
        isThinking = shown.isThinking
    }

    /// While the app is open, a reply that receives nothing for too long is sent
    /// again once, then reported, so the spinner never runs on and on.
    private func monitorStall(_ id: UUID) {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, let reply = self.activeReply, reply.id == id else { return }
                // Away from the app the background copy and checkReplyOnReturn take over.
                if reply.leftApp || UIApplication.shared.applicationState != .active { continue }
                // Models that reason silently before answering get longer.
                let limit = self.aiProviderManager.control(for: reply.model) == .effort
                    ? Self.silentThinkingTimeout : Self.inAppStallTimeout
                if Date().timeIntervalSince(reply.lastProgress) > limit {
                    self.restartIfStalled(id, after: 0)
                    return
                }
            }
        }
    }

    static var inAppStallTimeout: TimeInterval = 45
    static var silentThinkingTimeout: TimeInterval = 150

    private func isCurrentReply(_ id: UUID?) -> Bool {
        guard let id else { return true } // image path and legacy callers
        return activeReply?.id == id
    }

    /// Ends the reply: drops its background copy and forgets it.
    private func finishReply(_ id: UUID?) {
        guard let id, activeReply?.id == id else { return }
        if let jobID = activeReply?.jobID {
            BackgroundReplyService.shared.cancel(jobID: jobID)
        }
        activeReply = nil
    }

    /// The app is going to the background with a reply still coming: hand the
    /// same request to the background session so it finishes while suspended.
    func handOffActiveReplyToBackground() {
        guard var reply = activeReply else { return }
        reply.leftApp = true
        defer { activeReply = reply }
        guard reply.jobID == nil, let systemPrompt = reply.systemPrompt,
              let provider = aiProviderManager.getProvider(for: reply.model) else { return }
        let definition = aiProviderManager.getModel(id: reply.model)
        let inputs = BackgroundReplyRequests.Inputs(
            provider: provider.name,
            model: reply.model,
            systemPrompt: systemPrompt,
            userMessage: reply.text,
            apiKey: aiProviderManager.getAPIKey(for: provider.name),
            temperature: temperature,
            topP: topP,
            effort: effort,
            control: definition?.control ?? .sampling,
            maxOutputTokens: definition?.maxOutputTokens ?? 16_000
        )
        guard let request = BackgroundReplyRequests.request(for: inputs) else { return }
        let jobID = reply.id.uuidString
        if BackgroundReplyService.shared.submit(request, jobID: jobID, provider: provider.name) {
            reply.jobID = jobID
            print("📨 Reply handed to the background session (\(provider.name))")
        }
    }

    /// The background copy finished. Show it if the live stream has not already.
    func collectBackgroundReply(jobID: String) {
        guard let outcome = BackgroundReplyService.shared.outcome(jobID: jobID) else { return }
        guard let reply = activeReply, reply.jobID == jobID else {
            // No reply waiting for it: the app was closed meanwhile. Keep a
            // finished reply rather than lose it.
            BackgroundReplyService.shared.removeOutcome(jobID: jobID)
            if let text = outcome.text { presentReply(text) }
            return
        }
        BackgroundReplyService.shared.removeOutcome(jobID: jobID)
        if let text = outcome.text {
            print("📬 Reply delivered by the background session")
            reply.task?.cancel()
            activeReply = nil
            resetStreaming()
            presentReply(text)
            isLoading = false
            errorMessage = nil
        } else {
            print("⚠️ Background copy failed: \(outcome.error ?? "unknown")")
            activeReply?.jobID = nil
            restartIfStalled(reply.id, after: 0)
        }
    }

    /// Back in the app: collect a finished background reply, and make sure a
    /// stalled one cannot spin forever.
    func checkReplyOnReturn() {
        guard let reply = activeReply, reply.leftApp else { return }
        if let jobID = reply.jobID, BackgroundReplyService.shared.outcome(jobID: jobID) != nil {
            collectBackgroundReply(jobID: jobID)
            return
        }
        // With a background copy running, give it time; without one, restart
        // soon if the live stream has gone quiet.
        restartIfStalled(reply.id, after: reply.jobID == nil ? Self.stallTimeout : Self.backgroundTimeout)
    }

    static var stallTimeout: TimeInterval = 20
    static var backgroundTimeout: TimeInterval = 180

    /// Sends the request again if reply `id` has still not arrived after `delay`.
    private func restartIfStalled(_ id: UUID, after delay: TimeInterval) {
        Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard let self, let reply = self.activeReply, reply.id == id else { return }
            if UIApplication.shared.applicationState != .active { return } // retried on return
            guard !reply.restarted else {
                reply.task?.cancel()
                self.activeReply = nil
                self.resetStreaming()
                self.isLoading = false
                self.errorMessage = "The reply did not arrive. Check your connection and try again."
                return
            }
            print("🔁 Reply stalled; sending it again")
            self.resetStreaming()
            reply.task?.cancel()
            if let jobID = reply.jobID { BackgroundReplyService.shared.cancel(jobID: jobID) }
            self.startReply(text: reply.text, currentCode: reply.currentCode, restarted: true)
        }
    }

    /// Shows a finished reply in the chat.
    private func presentReply(_ response: String) {
        let processedResponse = processResponseForActions(ReplyText.visible(response).text)
        messages.append(ChatMessage(
            id: UUID().uuidString,
            content: processedResponse,
            isUser: false,
            timestamp: Date(),
            libraryId: library3DManager.selectedLibrary.id
        ))
    }

    /// Replies that finished after the app was closed, shown at the next launch.
    private func collectOrphanedReplies() {
        for outcome in BackgroundReplyService.shared.uncollectedOutcomes() {
            BackgroundReplyService.shared.removeOutcome(jobID: outcome.jobID)
            if let text = outcome.text { presentReply(text) }
        }
    }

    func sendMessageWithImages(_ text: String, images: [UIImage], currentCode: String? = nil) {
        // Display user message in chat with image count indicator
        let messageContent = images.count == 1 ?
            "\(text) [📷 1 image]" :
            "\(text) [📷 \(images.count) images]"

        let userMessage = ChatMessage(
            id: UUID().uuidString,
            content: messageContent,
            isUser: true,
            timestamp: Date(),
            libraryId: library3DManager.selectedLibrary.id
        )
        messages.append(userMessage)

        Task {
            await processUserMessageWithImages(text, images: images, currentCode: currentCode)
        }
    }

    // MARK: - Image Compression Helper

    /// Compresses an image to fit within the provider's size limit
    /// - Parameters:
    ///   - image: The UIImage to compress
    ///   - maxSize: Maximum size in bytes
    ///   - index: Image index for logging
    /// - Returns: Compressed JPEG data or nil if compression failed
    private func compressImage(_ image: UIImage, maxSize: Int, index: Int) -> Data? {
        print("🖼️ Compressing image \(index): original size \(image.size.width)x\(image.size.height)")

        // IMPORTANT: Account for base64 encoding overhead (~33% increase)
        // Target 75% of maxSize to ensure base64 encoded version fits
        let targetSize = Int(Double(maxSize) * 0.75)
        print("🎯 Target size (accounting for base64 overhead): \(String(format: "%.2f", Double(targetSize) / 1024.0 / 1024.0))MB")

        // Start with high quality
        var compressionQuality: CGFloat = 0.8
        var imageData = image.jpegData(compressionQuality: compressionQuality)

        // If still too large, reduce quality progressively
        while let data = imageData, data.count > targetSize && compressionQuality > 0.1 {
            compressionQuality -= 0.1
            imageData = image.jpegData(compressionQuality: compressionQuality)
            if let data = imageData {
                print("🔄 Trying quality \(String(format: "%.1f", compressionQuality)): \(String(format: "%.2f", Double(data.count) / 1024.0 / 1024.0))MB")
            }
        }

        // If still too large after quality reduction, resize the image
        if let data = imageData, data.count > targetSize {
            print("📐 Image still too large after quality reduction, resizing...")

            // Calculate scale factor to get under size limit
            // Rough estimate: reducing dimensions by 50% reduces file size by ~75%
            var scale: CGFloat = 0.8
            var resizedImage = resizeImage(image, scale: scale)
            imageData = resizedImage?.jpegData(compressionQuality: 0.7)

            // Keep reducing size if needed
            while let data = imageData, data.count > targetSize && scale > 0.2 {
                scale -= 0.1
                resizedImage = resizeImage(image, scale: scale)
                imageData = resizedImage?.jpegData(compressionQuality: 0.7)
                if let data = imageData {
                    print("🔄 Trying scale \(String(format: "%.1f", scale)): \(String(format: "%.2f", Double(data.count) / 1024.0 / 1024.0))MB")
                }
            }
        }

        if let finalData = imageData {
            let finalSizeMB = Double(finalData.count) / 1024.0 / 1024.0
            let base64Size = finalData.base64EncodedString().count
            let base64SizeMB = Double(base64Size) / 1024.0 / 1024.0
            print("✅ Compressed image \(index): \(String(format: "%.2f", finalSizeMB))MB raw, \(String(format: "%.2f", base64SizeMB))MB base64-encoded")
            return finalData
        }

        print("❌ Failed to compress image \(index) to acceptable size")
        return nil
    }

    /// Resizes an image by a scale factor
    private func resizeImage(_ image: UIImage, scale: CGFloat) -> UIImage? {
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    private func processUserMessageWithImages(_ text: String, images: [UIImage], currentCode: String?, isRetry: Bool = false) async {
        // SAFETY CHECK: Force migration away from non-serverless models
        if selectedModel == "Qwen/Qwen2.5-Coder-32B-Instruct" {
            print("🚨 SAFETY CHECK: Detected non-serverless model '\(selectedModel)' - forcing migration!")
            selectedModel = "zai-org/GLM-5.3-Flash"
            UserDefaults.standard.set(selectedModel, forKey: "XRAiAssistant_SelectedModel")
            print("✅ Migrated to: \(selectedModel)")
        }

        isLoading = true
        errorMessage = nil

        do {
            // Get provider's max image size
            guard let provider = aiProviderManager.getProvider(for: selectedModel) else {
                throw AIProviderError.modelNotSupported
            }

            let maxImageSize = provider.capabilities.maxImageSize
            print("📏 Provider max image size: \(maxImageSize / 1024 / 1024)MB")

            // Convert UIImages to AIImageContent with intelligent compression
            var imageContents: [AIImageContent] = []
            for (index, image) in images.enumerated() {
                // Compress image to fit within provider's limits
                guard let imageData = compressImage(image, maxSize: maxImageSize, index: index) else {
                    print("❌ Failed to compress image \(index)")
                    continue
                }

                let imageContent = AIImageContent(
                    data: imageData,
                    mimeType: "image/jpeg",
                    filename: "image_\(index).jpg"
                )
                imageContents.append(imageContent)
            }

            print("📸 Sending message with \(imageContents.count) images")

            // Verify provider supports vision (already checked above, but double-check)
            if !provider.capabilities.supportsVision {
                errorMessage = "⚠️ The selected model '\(selectedModel)' does not support image inputs. Please select a vision-capable model like GPT-4o, Claude Opus 4, or Gemini 2.5 Pro."
                isLoading = false
                return
            }

            // Create multimodal message with text and images
            var contentItems: [AIMessageContentType] = [.text(text)]
            for imageContent in imageContents {
                contentItems.append(.image(imageContent))
            }

            // Create system prompt
            let fullSystemPrompt = createSystemPrompt(currentCode: currentCode)

            // Build message array
            let messages = [
                AIMessage(role: .system, text: fullSystemPrompt),
                AIMessage(role: .user, content: contentItems)
            ]

            print("🚀 Calling AI provider with multimodal message")

            // Stream response from AI provider, inside a background task so
            // leaving the app does not cut the reply off.
            let fullResponse = try await BackgroundRequest.run("AI reply") {
                let stream = try await aiProviderManager.generateResponse(
                    messages: messages,
                    modelId: selectedModel,
                    temperature: temperature,
                    topP: topP,
                    effort: effort
                )
                var collected = ""
                for try await chunk in stream {
                    collected += chunk
                }
                return collected
            }

            print("✅ Received complete response: \(fullResponse.count) characters")

            // Process response for actions
            let processedResponse = processResponseForActions(fullResponse)

            let assistantMessage = ChatMessage(
                id: UUID().uuidString,
                content: processedResponse,
                isUser: false,
                timestamp: Date(),
                libraryId: library3DManager.selectedLibrary.id
            )
            self.messages.append(assistantMessage)

        } catch where !isRetry && BackgroundRequest.isInterruption(error) {
            print("📶 Image request interrupted (\(error.localizedDescription)); will send again")
            holdInterruptedRequest { [weak self] in
                await self?.processUserMessageWithImages(text, images: images, currentCode: currentCode, isRetry: true)
            }
            return
        } catch {
            // The image cases carry their own specifics and stay as they are.
            // Everything else goes through the shared classifier, so the user
            // gets a cause and a next step rather than a localizedDescription.
            if let providerError = error as? AIProviderError,
               case let .imageNotSupported(provider) = providerError {
                errorMessage = "\(provider) does not support image inputs.\n\nPick a vision-capable model in Settings."
            } else if let providerError = error as? AIProviderError,
                      case let .imageTooLarge(size, max) = providerError {
                errorMessage = "That image is \(size / 1024 / 1024)MB, over the \(max / 1024 / 1024)MB limit.\n\nUse a smaller image."
            } else if let providerError = error as? AIProviderError,
                      case let .invalidImageFormat(format) = providerError {
                errorMessage = "\(format) images are not supported.\n\nUse a PNG or JPEG."
            } else {
                errorMessage = AIErrorClassifier.classify(error, provider: currentProviderDisplayName).asMessage
            }
            print("❌ Multimodal error: \(error)")
        }

        isLoading = false
    }

    private func processUserMessage(_ text: String, currentCode: String?, isRetry: Bool = false, replyID: UUID? = nil) async {
        // SAFETY CHECK: Force migration away from non-serverless models
        if selectedModel == "Qwen/Qwen2.5-Coder-32B-Instruct" {
            print("🚨 SAFETY CHECK: Detected non-serverless model '\(selectedModel)' - forcing migration!")
            selectedModel = "zai-org/GLM-5.3-Flash"
            UserDefaults.standard.set(selectedModel, forKey: "XRAiAssistant_SelectedModel")
            print("✅ Migrated to: \(selectedModel)")
        }

        isLoading = true
        errorMessage = nil

        do {
            // Create system prompt with context
            let fullSystemPrompt = createSystemPrompt(currentCode: currentCode)
            if let replyID, activeReply?.id == replyID {
                activeReply?.systemPrompt = fullSystemPrompt
            }

            // Use simple inference for chat
            let response = try await BackgroundRequest.run("AI reply") {
                try await callLlamaInference(userMessage: text, systemPrompt: fullSystemPrompt) { [weak self] partial in
                    guard let replyID else { return }
                    Task { @MainActor in self?.streamProgress(partial, replyID: replyID) }
                }
            }

            // Already shown by the background session, or superseded by a restart.
            guard isCurrentReply(replyID) else { return }
            finishReply(replyID)
            resetStreaming()

            // Process response for potential actions (reasoning text is not shown)
            let processedResponse = processResponseForActions(ReplyText.visible(response).text)

            // DEBUG: Log the COMPLETE processed response before saving
            print("🔍 ===== PROCESSED RESPONSE DEBUG (BEFORE SAVING) =====")
            print("📏 Total length: \(processedResponse.count) characters")
            print("📝 First 500 chars:\n\(processedResponse.prefix(500))")
            print("📝 Last 500 chars:\n\(processedResponse.suffix(500))")

            // Check if code blocks are properly formed
            let openingBackticks = processedResponse.components(separatedBy: "```").count - 1
            print("📊 Number of ``` markers: \(openingBackticks) (should be even!)")

            if openingBackticks % 2 != 0 {
                print("⚠️ WARNING: Odd number of ``` markers - code blocks are MALFORMED!")
            } else {
                print("✅ Code blocks appear properly closed")
            }

            // Check for specific markers
            if processedResponse.contains("[INSERT_CODE]") {
                print("✅ Contains [INSERT_CODE] marker")
            }
            if processedResponse.contains("[/INSERT_CODE]") {
                print("✅ Contains [/INSERT_CODE] marker")
            } else if processedResponse.contains("[INSERT_CODE]") {
                print("⚠️ WARNING: Has opening [INSERT_CODE] but missing closing [/INSERT_CODE]")
            }
            if processedResponse.contains("[RUN_SCENE]") {
                print("✅ Contains [RUN_SCENE] marker (this should have been removed!)")
            }
            print("🔍 ===== END PROCESSED RESPONSE DEBUG =====")

            let assistantMessage = ChatMessage(
                id: UUID().uuidString,
                content: processedResponse,
                isUser: false,
                timestamp: Date(),
                libraryId: library3DManager.selectedLibrary.id
            )
            messages.append(assistantMessage)
            
        } catch where !isCurrentReply(replyID) || error is CancellationError || (error as? URLError)?.code == .cancelled {
            // Superseded: the background session delivered it, or it was restarted.
            return
        } catch where activeReply?.jobID != nil && BackgroundRequest.isInterruption(error) {
            // The live stream dropped, but the background copy is still running.
            print("📶 Stream interrupted; waiting for the background copy")
            return
        } catch where !isRetry && BackgroundRequest.isInterruption(error) {
            print("📶 Request interrupted (\(error.localizedDescription)); will send again")
            if let replyID, let reply = activeReply, reply.id == replyID {
                holdInterruptedRequest { [weak self] in
                    self?.startReply(text: reply.text, currentCode: reply.currentCode, restarted: true)
                }
            } else {
                holdInterruptedRequest { [weak self] in
                    await self?.processUserMessage(text, currentCode: currentCode, isRetry: true)
                }
            }
            return
        } catch {
            finishReply(replyID)
            resetStreaming()
            // Provide user-friendly error messages for common issues
            if let providerError = error as? AIProviderError {
                switch providerError {
                case .configurationError(let message):
                    if message.contains("API key not configured") {
                        errorMessage = "⚠️ API Key Required: Please configure your \(providerNameForSelectedModel) API key in Settings (gear icon). Get your API key at \(apiKeyURLForSelectedModel)"
                    } else {
                        errorMessage = "Configuration Error: \(message)"
                    }
                default:
                    errorMessage = "Provider Error: \(providerError.localizedDescription)"
                }
            } else if error.localizedDescription.contains("Invalid API key") {
                errorMessage = "⚠️ Invalid API Key: Please check your \(providerNameForSelectedModel) API key in Settings (gear icon). Get your API key at \(apiKeyURLForSelectedModel)"
            } else if error.localizedDescription.contains("401") {
                errorMessage = "⚠️ Authentication Failed: Please verify your \(providerNameForSelectedModel) API key in Settings (gear icon)."
            } else {
                errorMessage = "Failed to get response: \(error.localizedDescription)"
            }
            print("Chat error: \(error)")
        }
        
        isLoading = false
    }
    
    /// Keeps the spinner up and sends the request again: straight away if the app
    /// is in front, otherwise as soon as the user comes back to it.
    private func holdInterruptedRequest(_ retry: @escaping () async -> Void) {
        interruptedRequests.hold { Task { await retry() } }
        if UIApplication.shared.applicationState == .active {
            interruptedRequests.resume()
        }
    }

    private func createSystemPrompt(currentCode: String?) -> String {
        // Use library-specific prompt with context
        let prompt = library3DManager.getLibrarySpecificPrompt(
            for: "", // No specific user message for system prompt
            currentCode: currentCode
        )
        
        print("System Prompt (\(library3DManager.selectedLibrary.displayName)): \(prompt.prefix(200))...")
        return prompt
    }
    
    internal func callLlamaInference(
        userMessage: String,
        systemPrompt: String,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> String {
        print("🎯 Using selected model: \(selectedModel)")
        
        // A model owned by a registered provider must never fall through to the
        // Together.ai path below: posting e.g. an OpenAI model id to Together
        // returns a model_not_available 404 that hides the real failure.
        if let provider = aiProviderManager.getProvider(for: selectedModel) {
            print("📍 Routing to: New Provider System (\(provider.name))")
            return try await callNewProviderSystem(userMessage: userMessage, systemPrompt: systemPrompt, onProgress: onProgress)
        }

        // Legacy path: only models with no registered provider reach here.
        print("🔧 LlamaStack toggle: \(useLlamaStackForLlamaModels ? "ENABLED" : "DISABLED (using Together.ai for all)")")

        // Route to appropriate service based on configuration toggle
        if useLlamaStackForLlamaModels && selectedModel.contains("meta-llama") {
            // Use LlamaStackClient for Llama models (when toggle is enabled)
            print("📍 Routing to: LlamaStackClient (local)")
            return try await callLlamaStackModel(userMessage: userMessage, systemPrompt: systemPrompt)
        } else {
            // Use AIProxy + Together.ai for ALL models (default behavior)
            print("📍 Routing to: Together.ai (cloud)")
            return try await callTogetherAIModel(userMessage: userMessage, systemPrompt: systemPrompt)
        }
    }
    
    private func callNewProviderSystem(
        userMessage: String,
        systemPrompt: String,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> String {
        print("🔧 New Provider System called with model: \(selectedModel)")
        let activeProvider = providerNameForSelectedModel
        let keyState = aiProviderManager.getAPIKey(for: activeProvider) == "changeMe" ? "NOT_CONFIGURED (changeMe)" : "CONFIGURED"
        print("🔑 \(activeProvider) API key status: \(keyState)")
        
        let messages = [
            AIMessage(role: .system, text: systemPrompt),
            AIMessage(role: .user, text: userMessage)
        ]
        
        print("📤 Sending request to AIProviderManager...")
        let stream = try await aiProviderManager.generateResponse(
            messages: messages,
            modelId: selectedModel,
            temperature: temperature,
            topP: topP,
            effort: effort
        )
        
        var fullResponse = ""
        print("📥 Receiving streaming response...")
        
        for try await chunk in stream {
            fullResponse += chunk
            onProgress?(fullResponse)
        }
        
        print("✅ New provider system response complete, length: \(fullResponse.count)")
        return fullResponse
    }
    
    func getModelDisplayName(_ modelId: String) -> String {
        // Try new provider system first
        if let model = aiProviderManager.getModel(id: modelId) {
            return model.displayName
        }
        
        // Fallback to legacy system
        switch modelId {
        case "deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free":
            return "DeepSeek R1 70B (Free)"
        case "meta-llama/Llama-3.3-70B-Instruct-Turbo-Free":
            return "Llama 3.3 70B (Free)"
        case "meta-llama/Meta-Llama-3-8B-Instruct-Lite":
            return "Llama 3 8B Lite"
        case "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo":
            return "Llama 3.1 8B Turbo"
        case "Qwen/Qwen2.5-7B-Instruct-Turbo":
            return "Qwen 2.5 7B Turbo"
        default:
            return modelId
        }
    }
    
    func getModelDescription(_ modelId: String) -> String {
        // Try new provider system first
        if let model = aiProviderManager.getModel(id: modelId) {
            let pricing = model.pricing.isEmpty ? "" : " - \(model.pricing)"
            return "\(model.description)\(pricing)"
        }
        
        // Fallback to legacy system
        switch modelId {
        case "deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free":
            return "FREE - Advanced reasoning & coding"
        case "meta-llama/Llama-3.3-70B-Instruct-Turbo-Free":
            return "FREE - Latest large model"
        case "meta-llama/Meta-Llama-3-8B-Instruct-Lite":
            return "CHEAPEST - $0.10/1M tokens"
        case "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo":
            return "Good balance - $0.18/1M tokens"
        case "Qwen/Qwen2.5-7B-Instruct-Turbo":
            return "Fast coding - $0.30/1M tokens"
        default:
            return "Custom model"
        }
    }
    
    func getParameterDescription() -> String {
        if usesEffortControl {
            return "\(effort.displayName) Reasoning - \(effort.summary)"
        }
        switch (temperature, topP) {
        case (0.0...0.3, 0.1...0.5):
            return "Precise & Focused - Perfect for debugging"
        case (0.4...0.8, 0.6...0.9): 
            return "Balanced Creativity - Ideal for most scenes"
        case (0.9...2.0, 0.9...1.0):
            return "Experimental Mode - Maximum innovation"
        default:
            return "Custom Configuration"
        }
    }
    
    
    private func callLlamaStackModel(userMessage: String, systemPrompt: String) async throws -> String {
        let messages: [Components.Schemas.Message] = [
            .system(Components.Schemas.SystemMessage(
                role: .system,
                content: .case1(systemPrompt)
            )),
            .user(Components.Schemas.UserMessage(
                role: .user,
                content: .case1(userMessage)
            ))
        ]
        
        var fullResponse = ""
        
        print("🚀 Using LlamaStackClient for model: \(selectedModel)")
        print("🔧 LlamaStack config: stream=true (using server default max_tokens)")
        
        let streamingRequest = Components.Schemas.ChatCompletionRequest(
            model_id: selectedModel,
            messages: messages,
            stream: true
        )
        
        let stream = try await inference.chatCompletion(request: streamingRequest)
        print("✅ LlamaStack stream created successfully")
        
        // Standard processing for Llama models with error handling
        for try await chunk in stream {
            print("📦 Processing chunk from LlamaStack...")
            do {
                let chunkResult = try processChunk(chunk, modelId: selectedModel)
                fullResponse += chunkResult
                if !chunkResult.isEmpty {
                    print("📦 Added chunk content: '\(chunkResult.prefix(20))...' (total: \(fullResponse.count))")
                }
            } catch {
                print("⚠️ Error processing individual chunk: \(error)")
                print("🔍 DEBUG: Problematic chunk: \(chunk)")
                // Continue processing other chunks
            }
        }
        
        print("✅ Stream completed, response length: \(fullResponse.count)")
        
        // Check if we hit token limits or other issues
        if fullResponse.isEmpty {
            print("⚠️ WARNING: LlamaStack returned empty response - this might indicate an API issue")
        } else if fullResponse.count < 500 {
            print("⚠️ WARNING: Response seems short (\(fullResponse.count) chars) - might be truncated")
        }
        return fullResponse
    }
    
    private func callTogetherAIModel(userMessage: String, systemPrompt: String) async throws -> String {
        // OPTIMIZATION: Using configurable retry count to minimize multiple API calls
        return try await callTogetherAIModelWithRetry(userMessage: userMessage, systemPrompt: systemPrompt, maxRetries: maxRetryAttempts)
    }
    
    private func callTogetherAIModelWithRetry(userMessage: String, systemPrompt: String, maxRetries: Int) async throws -> String {
        print("🚀 Using AIProxy + Together.ai for model: \(selectedModel) (retry attempts remaining: \(maxRetries))")
        
        // Create messages for AIProxy format
        let messages = [
            TogetherAIMessage(content: systemPrompt, role: .system),
            TogetherAIMessage(content: userMessage, role: .user)
        ]
        
        // Enhanced request body with explicit parameters for better completion
        // Note: Now all models use Together.ai which supports maxTokens parameter
        let requestBody = TogetherAIChatCompletionRequestBody(
            messages: messages,
            model: selectedModel,  // Use model name as-is (NIM endpoint should work)
            maxTokens: 4000,  // ✅ FIXED: Added maxTokens to prevent 400 errors
            stream: true,
            temperature: temperature,
            topP: topP
        )
        
        print("✅ Created Together.ai request for model: \(selectedModel)")
        print("🔧 Together.ai config: stream=true, temperature=\(temperature), top-p=\(topP), max-tokens=4000")
        
        // Use streaming chat completion with enhanced monitoring
        var fullResponse = ""
        var chunkCount = 0
        var lastChunkTime = Date()
        let streamStartTime = Date()
        
        do {
            let streamingResponse = try await togetherAIService.streamingChatCompletionRequest(body: requestBody)
            print("✅ Together.ai stream created successfully")
            
            for try await chunk in streamingResponse {
                chunkCount += 1
                let currentTime = Date()
                let timeSinceLastChunk = currentTime.timeIntervalSince(lastChunkTime)
                lastChunkTime = currentTime
                
                if let content = chunk.choices.first?.delta.content {
                    fullResponse += content
                    print("📦 Chunk \(chunkCount): '\(content.prefix(30))...' (+\(String(format: "%.2f", timeSinceLastChunk))s)")
                }
                
                // Check for completion indicators in chunk
                if let finishReason = chunk.choices.first?.finishReason {
                    print("🏁 Stream finish reason: \(finishReason)")
                    break
                }
                
                // Timeout detection - if no chunks for 30 seconds, something's wrong
                if timeSinceLastChunk > 30.0 {
                    print("⚠️ Chunk timeout detected - stream may be stalled")
                    throw StreamError.chunkTimeout
                }
            }
            
            let totalStreamTime = Date().timeIntervalSince(streamStartTime)
            print("✅ Together.ai stream completed: \(chunkCount) chunks, \(fullResponse.count) chars, \(String(format: "%.2f", totalStreamTime))s")
            
            // OPTIMIZATION: Simplified validation - only reject truly empty or severely truncated responses
            if fullResponse.isEmpty {
                print("❌ Empty response - critical failure")
                if maxRetries > 0 {
                    print("🔄 Retrying due to empty response...")
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay for empty responses
                    return try await callTogetherAIModelWithRetry(
                        userMessage: userMessage, 
                        systemPrompt: systemPrompt, 
                        maxRetries: maxRetries - 1
                    )
                } else {
                    throw APIError.emptyResponse
                }
            } else if fullResponse.count < minimumResponseLength {
                print("⚠️ Very short response (\(fullResponse.count) chars) - likely truncated: '\(fullResponse)'")
                if maxRetries > 0 {
                    print("🔄 Retrying due to truncated response...")
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    return try await callTogetherAIModelWithRetry(
                        userMessage: userMessage, 
                        systemPrompt: systemPrompt, 
                        maxRetries: maxRetries - 1
                    )
                } else {
                    print("⚠️ Using short response (no retries left)")
                    return fullResponse
                }
            } else {
                print("✅ Response validation passed (\(fullResponse.count) chars)")
                return fullResponse
            }
            
        } catch {
            print("❌ Together.ai error: \(error)")
            print("Error details: \(error.localizedDescription)")
            
            // OPTIMIZATION: Only retry on critical network/server errors, not client errors (400, 401, etc.)
            let shouldRetry = shouldRetryError(error)
            if maxRetries > 0 && shouldRetry {
                print("🔄 Retrying request due to retriable error...")
                // Exponential backoff: longer delay for retries
                let delay = Double(2 - maxRetries + 1) * 2.0 // 2s, 4s delays
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await callTogetherAIModelWithRetry(
                    userMessage: userMessage, 
                    systemPrompt: systemPrompt, 
                    maxRetries: maxRetries - 1
                )
            } else {
                print("❌ Not retrying: \(shouldRetry ? "No retries left" : "Error not retriable")")
                throw error
            }
        }
    }
    
    
    private func processChunk(_ chunk: Components.Schemas.ChatCompletionResponseStreamChunk, modelId: String) throws -> String {
        print("🔍 DEBUG: Processing chunk for model: \(modelId)")
        print("🔍 DEBUG: Chunk structure: \(chunk)")
        
        // Check for stop reasons and completion signals
        if let stopReason = chunk.event.stop_reason {
            print("🏁 Stream stop reason: \(stopReason)")
            if case .out_of_tokens = stopReason {
                print("⚠️ WARNING: Response truncated due to token limit - consider increasing max_tokens")
            }
        }
        
        if case .complete = chunk.event.event_type {
            print("🏁 Stream marked as complete")
            
            // Log token usage if available
            if let metrics = chunk.metrics {
                for metric in metrics {
                    if case .case1(let value) = metric.value {
                        print("📊 \(metric.metric): \(value)")
                    }
                }
            }
        }
        
        // Access the event delta content directly
        switch (chunk.event.delta) {
        case .text(let textContent):
            print("✅ Found text content: '\(textContent.text.prefix(50))...'")
            return textContent.text
        case .image(_):
            print("📸 Found image content (skipping)")
            return "" // Handle image content if needed
        case .tool_call(_):
            print("🔧 Found tool call content (skipping)")
            return "" // Handle tool calls if needed
        }
    }
    
    private func processResponseForActions(_ response: String) -> String {
        var processedResponse = response
        
        print("=== PROCESSING AI RESPONSE (\(selectedModel)) ===")
        print("Full response length: \(response.count)")
        print("FULL RESPONSE: \(response)")
        print("Looking for [INSERT_CODE] tags...")
        
        // Debug: Check if the response contains the tags at all
        if response.contains("[INSERT_CODE]") {
            print("✅ Found [INSERT_CODE] in response")
        } else {
            print("❌ No [INSERT_CODE] found in response")
        }
        
        if response.contains("```javascript") {
            print("✅ Found ```javascript in response")
        } else if response.contains("```typescript") {
            print("✅ Found ```typescript in response")
        } else if response.contains("```js") {
            print("✅ Found ```js in response")
        } else if response.contains("```") {
            print("✅ Found ``` blocks in response")
        } else {
            print("❌ No code blocks found in response")
        }
        
        // ENHANCED STRING EXTRACTION - Handle multiple patterns for [INSERT_CODE]
        print("Using enhanced string extraction...")
        
        // Pattern 1: [INSERT_CODE]```javascript ... ``` or ... [/INSERT_CODE] (improved)
        let directPatterns = ["[INSERT_CODE]```javascript", "[INSERT_CODE]```typescript", "[INSERT_CODE]```js", "[INSERT_CODE]```ts"]

        for pattern in directPatterns {
            if let startIndex = response.range(of: pattern)?.upperBound {
                print("Found direct pattern: \(pattern)")

                let remainingString = String(response[startIndex...])

                // Try to find [/INSERT_CODE] first (Qwen/most models use this)
                if let insertCodeEndRange = remainingString.range(of: "[/INSERT_CODE]") {
                    print("🔍 Found [/INSERT_CODE] tag, extracting code before it")

                    // Extract everything from startIndex to [/INSERT_CODE], then trim ``` if present
                    let codeRange = startIndex..<response.index(startIndex, offsetBy: remainingString.distance(from: remainingString.startIndex, to: insertCodeEndRange.lowerBound))
                    var extractedCode = String(response[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                    // Remove trailing ``` if present
                    if extractedCode.hasSuffix("```") {
                        extractedCode = String(extractedCode.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    if !extractedCode.isEmpty {
                        print("✅ Extracted code using [/INSERT_CODE] boundary: \(extractedCode.count) chars")
                        let correctedCode = fixBabylonJSCode(extractedCode)
                        // DON'T replace code blocks - we need them intact for "Run the Scene" button!
                        // Clean all display markers before returning
                        print("🧹 Cleaning display markers from response (early return path 1)...")
                        processedResponse = processedResponse.replacingOccurrences(of: "[INSERT_CODE]", with: "")
                        processedResponse = processedResponse.replacingOccurrences(of: "[/INSERT_CODE]", with: "")
                        processedResponse = processedResponse.replacingOccurrences(of: "[RUN_SCENE]", with: "")
                        injectCodeWithBuildSupport(correctedCode)
                        return processedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                // Fallback: look for closing ``` (old behavior for models that don't use [/INSERT_CODE])
                else if let endIndex = remainingString.range(of: "```")?.lowerBound {
                    print("🔍 No [/INSERT_CODE] found, using closing ``` marker")

                    let codeRange = startIndex..<response.index(startIndex, offsetBy: remainingString.distance(from: remainingString.startIndex, to: endIndex))
                    let extractedCode = String(response[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                    if !extractedCode.isEmpty {
                        print("✅ Extracted code using closing ``` marker: \(extractedCode.count) chars")
                        let correctedCode = fixBabylonJSCode(extractedCode)
                        // DON'T replace code blocks - we need them intact for "Run the Scene" button!
                        // Clean all display markers before returning
                        print("🧹 Cleaning display markers from response (early return path 2)...")
                        processedResponse = processedResponse.replacingOccurrences(of: "[INSERT_CODE]", with: "")
                        processedResponse = processedResponse.replacingOccurrences(of: "[/INSERT_CODE]", with: "")
                        processedResponse = processedResponse.replacingOccurrences(of: "[RUN_SCENE]", with: "")
                        injectCodeWithBuildSupport(correctedCode)
                        return processedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        
        // Pattern 2: ACTUAL Qwen format: [INSERT_CODE]\n```javascript\n...code...\n[/INSERT_CODE] (no closing ```)
        if let insertCodeStart = response.range(of: "[INSERT_CODE]"),
           let insertCodeEnd = response.range(of: "[/INSERT_CODE]") {
            print("Found complete [INSERT_CODE]...[/INSERT_CODE] block")
            
            // Extract everything between [INSERT_CODE] and [/INSERT_CODE]
            let blockRange = insertCodeStart.upperBound..<insertCodeEnd.lowerBound
            let fullBlock = String(response[blockRange])
            
            print("🔍 Full INSERT_CODE block:")
            print("'\(fullBlock)'")
            
            // Now find the ```javascript/typescript... part within this block (NO closing ``` expected)
            print("🔍 Looking for code language markers in block...")
            let codeLanguagePatterns = ["```javascript", "```typescript", "```js", "```ts"]
            
            for languagePattern in codeLanguagePatterns {
                if let codeStart = fullBlock.range(of: languagePattern) {
                    print("✅ Found \(languagePattern) at position in block")
                    
                    // Extract everything after the language marker until the end of the block
                    let afterCodeStart = codeStart.upperBound
                    let extractedCode = String(fullBlock[afterCodeStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    print("🔍 Raw extracted code length: \(extractedCode.count)")
                    print("🔍 Raw extracted code preview: '\(extractedCode.prefix(100))...'")
                    
                    if !extractedCode.isEmpty {
                        print("✅ Extracted code using ACTUAL Qwen pattern method with \(languagePattern)")
                        print("Code length: \(extractedCode.count)")
                        print("Code preview: \(extractedCode.prefix(300))...")

                        let correctedCode = fixBabylonJSCode(extractedCode)
                        // DON'T replace code blocks - we need them intact for "Run the Scene" button!
                        // Clean all display markers before returning
                        print("🧹 Cleaning display markers from response (early return path 3)...")
                        processedResponse = processedResponse.replacingOccurrences(of: "[INSERT_CODE]", with: "")
                        processedResponse = processedResponse.replacingOccurrences(of: "[/INSERT_CODE]", with: "")
                        processedResponse = processedResponse.replacingOccurrences(of: "[RUN_SCENE]", with: "")
                        injectCodeWithBuildSupport(correctedCode)
                        return processedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        print("⚠️ Extracted code is empty after trimming")
                    }
                }
            }
            
            // If no language patterns found, print debug info
            print("❌ Could not find any code language markers in block")
            print("🔍 Block starts with: '\(fullBlock.prefix(50))...'")
            print("🔍 Block contains 'javascript': \(fullBlock.contains("javascript"))")
            print("🔍 Block contains 'typescript': \(fullBlock.contains("typescript"))")
            print("🔍 Block contains '```': \(fullBlock.contains("```"))")
        }
        
        // ALWAYS look for regular code blocks as primary method for ALL models
        print("Looking for regular code blocks...")
        
        // DEBUG: Show actual response format around code blocks
        if let jsIndex = response.range(of: "```javascript") {
            let start = max(response.startIndex, response.index(jsIndex.lowerBound, offsetBy: -20))
            let end = min(response.endIndex, response.index(jsIndex.upperBound, offsetBy: 100))
            print("🔍 RESPONSE DEBUG: Context around ```javascript:")
            print("'\(response[start..<end])'")
        }
        
        // More flexible regex that handles text around code blocks
        let codeBlockRegex = try! NSRegularExpression(pattern: "```(?:javascript|typescript|js|ts)?\\s*\\n?([\\s\\S]+?)\\n?```", options: [.dotMatchesLineSeparators])
        let codeMatches = codeBlockRegex.matches(in: response, options: [], range: NSRange(response.startIndex..., in: response))
        
        print("Found \(codeMatches.count) regular code blocks for model: \(selectedModel)")
        
        for (index, match) in codeMatches.enumerated() {
            if let codeRange = Range(match.range(at: 1), in: response) {
                let code = String(response[codeRange])
                print("🔍 QWEN DEBUG: Code block \(index + 1) from \(selectedModel):")
                print("🔍 QWEN DEBUG: Full code content: \(code)")
                print("🔍 QWEN DEBUG: Code length: \(code.count)")
                print("🔍 QWEN DEBUG: Contains createScene: \(code.contains("createScene"))")
                print("🔍 QWEN DEBUG: Contains BABYLON: \(code.contains("BABYLON"))")
                print("🔍 QWEN DEBUG: Contains Scene: \(code.contains("Scene"))")
                print("🔍 QWEN DEBUG: Contains scene: \(code.contains("scene"))")
                print("🔍 QWEN DEBUG: Contains camera: \(code.contains("camera"))")
                print("🔍 QWEN DEBUG: Contains light: \(code.contains("light"))")
                print("🔍 QWEN DEBUG: Contains mesh: \(code.contains("mesh"))")
                print("🔍 QWEN DEBUG: Contains engine: \(code.contains("engine"))")
                print("🔍 QWEN DEBUG: Contains canvas: \(code.contains("canvas"))")
                print("🔍 QWEN DEBUG: Contains const: \(code.contains("const "))")
                print("🔍 QWEN DEBUG: Contains function: \(code.contains("function"))")
                print("🔍 QWEN DEBUG: Contains var: \(code.contains("var "))")
                print("🔍 QWEN DEBUG: Contains let: \(code.contains("let "))")

                // CRITICAL FIX: Check for A-Frame HTML FIRST to avoid false positives
                let isAFrameCode = code.contains("<a-scene") ||
                                   code.contains("<a-") ||
                                   code.contains("a-scene") ||
                                   code.contains("a-box") ||
                                   code.contains("a-sphere")

                print("🔍 QWEN DEBUG: isAFrameCode = \(isAFrameCode)")

                // Accept ANY code block that looks like Babylon.js code - be very flexible
                // BUT exclude A-Frame HTML which also contains "scene", "camera", "light"
                let isBabylonCode = !isAFrameCode && (
                                   code.contains("createScene") ||
                                   code.contains("BABYLON") ||
                                   code.contains("new Scene") ||
                                   code.contains("const scene") ||
                                   (code.contains("scene") && code.contains("const")) ||
                                   (code.contains("camera") && code.contains("const")) ||
                                   code.contains("mesh") ||
                                   code.contains("engine") ||
                                   (code.contains("canvas") && code.contains("const")))

                print("🔍 QWEN DEBUG: isBabylonCode = \(isBabylonCode)")
                
                if isBabylonCode {
                    print("✅ Found Babylon.js code in block \(index + 1) from model \(selectedModel)!")
                    print("=== REGULAR CODE BLOCK EXTRACTION ===")
                    print("EXTRACTED CODE (full):")
                    print(code)
                    print("=== END EXTRACTED CODE ===")
                    
                    // Auto-fix common Babylon.js API mistakes
                    let correctedCode = fixBabylonJSCode(code)
                    if correctedCode != code {
                        print("🔧 Code was auto-corrected for common API issues")
                        print("=== CORRECTED CODE (full) ===")
                        print(correctedCode)
                        print("=== END CORRECTED CODE ===")
                    } else {
                        print("ℹ️ No corrections needed - code looks good")
                    }
                    
                    // DON'T clean up code blocks - we need them for "Run the Scene" button!
                    // Comment out all code block removal to preserve markdown for saved conversations
                    // processedResponse = processedResponse.replacingOccurrences(of: "```javascript", with: "✅ Code extracted and ready!")
                    // processedResponse = processedResponse.replacingOccurrences(of: "```typescript", with: "✅ Code extracted and ready!")
                    // processedResponse = processedResponse.replacingOccurrences(of: "```js", with: "✅ Code extracted and ready!")
                    // processedResponse = processedResponse.replacingOccurrences(of: "```ts", with: "✅ Code extracted and ready!")
                    // processedResponse = processedResponse.replacingOccurrences(of: "```", with: "")

                    print("🎯 Calling enhanced code injection for model: \(selectedModel)")
                    injectCodeWithBuildSupport(correctedCode)
                    break
                }
            }
        }
        
        // Final check if no code found anywhere
        if codeMatches.isEmpty && !response.contains("[INSERT_CODE]") {
            print("❌ No code blocks found at all in response from model: \(selectedModel)")
        } else if !codeMatches.isEmpty {
            // If we found code blocks but none were injected, let's try a more permissive approach
            print("⚠️ Found \(codeMatches.count) code blocks but none were injected. Trying permissive mode for \(selectedModel)...")
            
            for (index, match) in codeMatches.enumerated() {
                if let codeRange = Range(match.range(at: 1), in: response) {
                    let code = String(response[codeRange])
                    print("🔄 FALLBACK DEBUG: Examining code block \(index + 1)")
                    print("🔄 FALLBACK DEBUG: Code content: \(code)")
                    
                    // VERY permissive - inject any code that looks like JavaScript
                    let isJavaScriptCode = code.contains("const ") || 
                                          code.contains("function") || 
                                          code.contains("var ") || 
                                          code.contains("let ") ||
                                          code.contains("=") ||
                                          code.contains("{") ||
                                          code.contains(";")
                    
                    print("🔄 FALLBACK DEBUG: isJavaScriptCode = \(isJavaScriptCode)")
                    
                    if isJavaScriptCode {
                        print("🔄 FALLBACK: Injecting JavaScript code block \(index + 1) from model \(selectedModel)")
                        print("FALLBACK CODE: \(code)")

                        let correctedCode = fixBabylonJSCode(code)
                        // DON'T remove code blocks - we need them for "Run the Scene" button!
                        // processedResponse = processedResponse.replacingOccurrences(of: "```", with: "✅ Code extracted (fallback mode)!")

                        print("🎯 FALLBACK: Calling onInsertCode for model: \(selectedModel)")
                        onInsertCode?(correctedCode)
                        break
                    } else if selectedModel.contains("Qwen") && code.count > 10 {
                        // ULTRA-AGGRESSIVE for Qwen models - inject ANY non-empty code block
                        print("🚨 ULTRA-FALLBACK for Qwen: Injecting ANY code block \(index + 1)")
                        print("🚨 ULTRA-FALLBACK CODE: \(code)")

                        let correctedCode = fixBabylonJSCode(code)
                        // DON'T remove code blocks - we need them for "Run the Scene" button!
                        // processedResponse = processedResponse.replacingOccurrences(of: "```", with: "✅ Code extracted (ultra-fallback)!")
                        
                        print("🎯 ULTRA-FALLBACK: Calling onInsertCode for Qwen model")
                        onInsertCode?(correctedCode)
                        break
                    }
                }
            }
        }
        
        // Look for run scene commands
        if response.contains("[RUN_SCENE]") {
            print("✅ Found [RUN_SCENE] command from model: \(selectedModel)")
            processedResponse = processedResponse.replacingOccurrences(of: "[RUN_SCENE]", with: "")
            print("🎬 Calling onRunScene for model: \(selectedModel)")
            onRunScene?()
        } else {
            print("ℹ️ No [RUN_SCENE] command found in response from model: \(selectedModel)")
        }

        // CRITICAL: Always strip display markers from the final response
        // These markers are used for code extraction but should NEVER appear in the displayed message
        print("🧹 Cleaning display markers from response...")
        processedResponse = processedResponse.replacingOccurrences(of: "[INSERT_CODE]", with: "")
        processedResponse = processedResponse.replacingOccurrences(of: "[/INSERT_CODE]", with: "")
        processedResponse = processedResponse.replacingOccurrences(of: "[RUN_SCENE]", with: "")
        print("✅ Display markers removed")

        let finalResponse = processedResponse.trimmingCharacters(in: .whitespacesAndNewlines)

        // DEBUG: Log what we're about to return from processResponseForActions
        print("🔍 ===== RETURNING FROM processResponseForActions =====")
        print("📏 Final response length: \(finalResponse.count) characters")
        print("📝 Final first 300 chars:\n\(finalResponse.prefix(300))")
        print("📝 Final last 300 chars:\n\(finalResponse.suffix(300))")

        // Count backticks to verify code blocks are closed
        let backtickCount = finalResponse.components(separatedBy: "```").count - 1
        print("📊 Final ``` count: \(backtickCount) \(backtickCount % 2 == 0 ? "✅ (even - good)" : "⚠️ (odd - BROKEN)")")
        print("🔍 ===== END processResponseForActions =====")

        return finalResponse
    }
    
    private func fixBabylonJSCode(_ code: String) -> String {
        var fixedCode = code
        
        // Fix common API mistakes
        print("🔧 Applying Babylon.js API fixes...")
        
        // CRITICAL: Remove RUN_SCENE and INSERT_CODE tags that cause JavaScript errors
        fixedCode = fixedCode.replacingOccurrences(of: "[RUN_SCENE]", with: "")
        fixedCode = fixedCode.replacingOccurrences(of: "[/RUN_SCENE]", with: "")
        fixedCode = fixedCode.replacingOccurrences(of: "[INSERT_CODE]", with: "")
        fixedCode = fixedCode.replacingOccurrences(of: "[/INSERT_CODE]", with: "")
        
        // Fix incorrect MeshBuilder references
        fixedCode = fixedCode.replacingOccurrences(of: "BABYLON.Mesh-Builder", with: "BABYLON.MeshBuilder")
        fixedCode = fixedCode.replacingOccurrences(of: "BABYLON.MeshBuilder.CreateCube", with: "BABYLON.MeshBuilder.CreateBox")
        fixedCode = fixedCode.replacingOccurrences(of: "BABYLON.MeshBuilder.CreateRing", with: "BABYLON.MeshBuilder.CreateTorus") // Ring doesn't exist, use Torus
        
        // Fix deprecated or incorrect methods
        fixedCode = fixedCode.replacingOccurrences(of: ".attachControl(", with: ".attachControls(")
        
        // Fix material issues
        fixedCode = fixedCode.replacingOccurrences(of: "BABYLON.Material", with: "BABYLON.StandardMaterial")
        
        // Fix camera issues
        fixedCode = fixedCode.replacingOccurrences(of: "BABYLON.Camera", with: "BABYLON.FreeCamera")
        
        // Fix light issues  
        fixedCode = fixedCode.replacingOccurrences(of: "BABYLON.Light", with: "BABYLON.HemisphericLight")
        
        // CRITICAL: Remove problematic canvas/engine creation code
        print("🔧 Removing problematic canvas/engine creation...")
        
        // Remove canvas creation
        if fixedCode.contains("document.createElement(\"canvas\")") {
            // Remove the canvas creation line and related code
            fixedCode = fixedCode.replacingOccurrences(of: "const canvas = document.createElement(\"canvas\");", with: "")
            fixedCode = fixedCode.replacingOccurrences(of: "document.body.appendChild(canvas);", with: "")
            print("  - Removed canvas creation (using existing playground canvas)")
        }
        
        // Remove engine creation
        if fixedCode.contains("new BABYLON.Engine(canvas, true)") {
            fixedCode = fixedCode.replacingOccurrences(of: "const engine = new BABYLON.Engine(canvas, true);", with: "")
            print("  - Removed engine creation (using existing playground engine)")
        }
        
        // Remove engine render loop
        if fixedCode.contains("engine.runRenderLoop") {
            let renderLoopPattern = "engine\\.runRenderLoop\\(\\(\\) => \\{[\\s\\S]*?\\}\\);"
            fixedCode = fixedCode.replacingOccurrences(of: renderLoopPattern, 
                                                        with: "", 
                                                        options: .regularExpression)
            print("  - Removed render loop (playground handles rendering)")
        }
        
        // Clean up any empty lines left behind
        fixedCode = fixedCode.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        fixedCode = fixedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Log what was fixed
        if fixedCode != code {
            print("🔧 Applied fixes:")
            if code.contains("[RUN_SCENE]") { print("  - Removed [RUN_SCENE] tags") }
            if code.contains("[INSERT_CODE]") { print("  - Removed [INSERT_CODE] tags") }
            if code.contains("Mesh-Builder") { print("  - Fixed Mesh-Builder → MeshBuilder") }
            if code.contains("CreateCube") { print("  - Fixed CreateCube → CreateBox") }
            if code.contains("CreateRing") { print("  - Fixed CreateRing → CreateTorus") }
            if code.contains("attachControl(") { print("  - Fixed attachControl → attachControls") }
            if code.contains("document.createElement") { print("  - Removed canvas creation") }
            if code.contains("new BABYLON.Engine") { print("  - Removed engine creation") }
            if code.contains("runRenderLoop") { print("  - Removed render loop") }
        }
        
        return fixedCode
    }
    
    // MARK: - Enhanced Code Injection with Build Support
    
    /// Handle code injection with automatic build for frameworks that require it
    func injectCodeWithBuildSupport(_ code: String) {
        let currentLibrary = library3DManager.selectedLibrary
        
        // Check if the current library requires building
        if let frameworkKind = BuildIntegration.getFrameworkKind(from: currentLibrary),
           frameworkKind.requiresBuild {
            
            print("🏗️ Framework \(frameworkKind.displayName) requires build - starting auto-build")
            
            // Use enhanced callback if available
            onInsertCodeWithBuild?(code, frameworkKind)
            
        } else {
            // Use regular injection for frameworks that don't need building
            print("📝 Framework \(currentLibrary.displayName) uses direct injection")
            onInsertCode?(code)
        }
    }
    
    /// True when the selected model takes a reasoning-effort level rather than
    /// temperature/top-p, so the settings UI can show the right control.
    var usesEffortControl: Bool {
        aiProviderManager.control(for: selectedModel) == .effort
    }

    /// Provider that owns the selected model, so key errors name the right service.
    var providerNameForSelectedModel: String {
        aiProviderManager.getProvider(for: selectedModel)?.name ?? "Together.ai"
    }

    var apiKeyURLForSelectedModel: String {
        switch providerNameForSelectedModel {
        case "OpenAI": return "https://platform.openai.com/api-keys"
        case "Anthropic": return "https://console.anthropic.com"
        case "Google AI": return "https://aistudio.google.com/apikey"
        case "xAI": return "https://console.x.ai"
        default: return "https://api.together.ai/settings/api-keys"
        }
    }

    // MARK: - Model Migration

    /// Retired or invalid model IDs mapped onto their current equivalents.
    ///
    /// Shared by the UserDefaults and SQLite settings loaders so a saved model
    /// migrates identically whichever store it came from.
    static let modelMigrations: [String: String] = [
        // Together: free tiers no longer served serverless -> GLM-5.3 Flash
        "deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free": "zai-org/GLM-5.3-Flash",
        "meta-llama/Llama-3.3-70B-Instruct-Turbo-Free": "zai-org/GLM-5.3-Flash",
        // Anthropic: retired 4.x snapshots -> Claude 5 series
        "claude-sonnet-4.5-20250514": "claude-sonnet-5",
        "claude-sonnet-4-5-20250514": "claude-sonnet-5",
        "claude-sonnet-4-5-20250929": "claude-sonnet-5",
        "claude-sonnet-4-5": "claude-sonnet-5",
        "claude-sonnet-4-0": "claude-sonnet-5",
        "claude-opus-4.5-20250514": "claude-opus-5",
        "claude-opus-4-1-20250805": "claude-opus-5",
        "claude-opus-4-1": "claude-opus-5",
        "claude-opus-4-5": "claude-opus-5",
        "claude-opus-4-0": "claude-opus-5",
        "claude-3-5-sonnet-20241022": "claude-sonnet-5",
        "claude-3-5-haiku-20241022": "claude-haiku-4-5",
        "claude-3-opus-20240229": "claude-opus-5",

        // OpenAI: o-series shuts down 2026-10-23, GPT-4o superseded
        "o1-2024-12-17": "gpt-5.6-sol",
        "o1": "gpt-5.6-sol",
        "o3-mini-2025-01-31": "gpt-5.6-terra",
        "o3-mini": "gpt-5.6-terra",
        "gpt-4o": "gpt-5.6-terra",
        "gpt-4o-mini": "gpt-5.6-luna",
        "gpt-5.2-pro": "gpt-6-astra",
        "gpt-5.2-chat-latest": "gpt-5.6-sol",

        // Together.ai non-serverless model migrations (to FREE alternatives)
        "Qwen/Qwen2.5-Coder-32B-Instruct": "zai-org/GLM-5.3-Flash"
    ]

    /// Default model to fall back to when a saved ID no longer exists at all.
    static func fallbackModel(for savedModel: String) -> String {
        if savedModel.contains("claude") || savedModel.contains("anthropic") {
            return "claude-opus-5"
        }
        if savedModel.hasPrefix("gpt-") || savedModel.hasPrefix("o1") || savedModel.hasPrefix("o3") {
            return "gpt-5.6-sol"
        }
        return "deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free"
    }

    // MARK: - Settings Persistence

    /// Save current settings to UserDefaults
    func saveSettings() {
        print("💾 Saving settings to UserDefaults...")
        
        // Save general settings
        UserDefaults.standard.set(systemPrompt, forKey: "XRAiAssistant_SystemPrompt")
        UserDefaults.standard.set(selectedModel, forKey: "XRAiAssistant_SelectedModel")
        UserDefaults.standard.set(temperature, forKey: "XRAiAssistant_Temperature")
        UserDefaults.standard.set(topP, forKey: "XRAiAssistant_TopP")
        UserDefaults.standard.set(effort.rawValue, forKey: "XRAiAssistant_Effort")

        // API keys, CodeSandbox's included, are kept in the Keychain by
        // AIProviderManager; nothing key-related goes into UserDefaults.

        // Update AI services with new API key if it changed
        updateAPIKey(apiKey)
        
        // The AIProviderManager handles its own persistence automatically
        
        print("✅ Settings saved successfully")
    }
    
    /// Load settings from UserDefaults
    internal func loadSettings() {
        print("📂 Loading settings from UserDefaults...")

        
        // Load API key (keep default if not found)
        // The legacy single key was moved into the Keychain by APIKeyStore when
        // AIProviderManager loaded; mirror Together.ai's key into `apiKey`.
        let togetherKey = aiProviderManager.getAPIKey(for: "Together.ai")
        apiKey = togetherKey != "changeMe" ? togetherKey : DEFAULT_API_KEY
        
        // Load system prompt (keep default if not found)
        if let savedSystemPrompt = UserDefaults.standard.string(forKey: "XRAiAssistant_SystemPrompt"), !savedSystemPrompt.isEmpty {
            systemPrompt = savedSystemPrompt
            print("📝 Loaded custom system prompt (\(savedSystemPrompt.count) characters)")
        }
        
        // Load model selection
        if let savedModel = UserDefaults.standard.string(forKey: "XRAiAssistant_SelectedModel") {
            print("📥 Found saved model in UserDefaults: \(savedModel)")

            // Check if model exists in either legacy models or new provider system
            let isLegacyModel = availableModels.contains(savedModel)
            let isProviderModel = aiProviderManager.getModel(id: savedModel) != nil

            let invalidModelMappings = ChatViewModel.modelMigrations

            // Check if we need to migrate from an invalid ID
            if let correctModel = invalidModelMappings[savedModel] {
                print("⚠️ Migrating invalid model '\(savedModel)' to '\(correctModel)'")

                // Update selected model immediately (no async needed - we're in init)
                selectedModel = correctModel

                // Save the corrected model to prevent future migrations
                UserDefaults.standard.set(correctModel, forKey: "XRAiAssistant_SelectedModel")
                print("✅ Migration complete: \(getModelDisplayName(correctModel))")
            } else if isLegacyModel || isProviderModel {
                selectedModel = savedModel
                print("🤖 Loaded saved model: \(getModelDisplayName(savedModel))")
            } else {
                // Model no longer exists, reset to default
                selectedModel = ChatViewModel.fallbackModel(for: savedModel)
                print("⚠️ Saved model '\(savedModel)' no longer available, switching to \(getModelDisplayName(selectedModel))")
                // Save the corrected model
                UserDefaults.standard.set(selectedModel, forKey: "XRAiAssistant_SelectedModel")
            }
        }
        
        // Load AI parameters
        let savedTemperature = UserDefaults.standard.object(forKey: "XRAiAssistant_Temperature") as? Double
        if let savedTemperature = savedTemperature {
            temperature = savedTemperature
            print("🌡️ Loaded saved temperature: \(savedTemperature)")
        }
        
        let savedTopP = UserDefaults.standard.object(forKey: "XRAiAssistant_TopP") as? Double
        if let savedTopP = savedTopP {
            topP = savedTopP
            print("🎯 Loaded saved top-p: \(savedTopP)")
        }

        if let savedEffort = UserDefaults.standard.string(forKey: "XRAiAssistant_Effort"),
           let parsed = AIEffort(rawValue: savedEffort) {
            effort = parsed
            print("🧠 Loaded saved effort: \(parsed.displayName)")
        }
        
        // Update AI services with loaded API key
        if apiKey != DEFAULT_API_KEY {
            updateAPIKey(apiKey)
        }
        
        print("✅ Settings loaded successfully")
    }
}

// MARK: - Supporting Types and Validation

enum StreamError: Error {
    case chunkTimeout
    case incompleteResponse
    case validationFailed
}

struct ResponseValidation {
    let isComplete: Bool
    let shouldRetry: Bool
    let issues: [String]
}

private func validateResponse(_ response: String, model: String) -> ResponseValidation {
    var issues: [String] = []
    var isComplete = true
    var shouldRetry = false
    
    // Basic completeness checks
    if response.isEmpty {
        issues.append("Empty response")
        isComplete = false
        shouldRetry = true
        return ResponseValidation(isComplete: false, shouldRetry: true, issues: issues)
    }
    
    // Check for minimum expected length (3D code should be substantial)
    if response.count < 100 {
        issues.append("Response too short (\(response.count) chars)")
        isComplete = false
        shouldRetry = true
    }
    
    // Check for expected Babylon.js patterns in response
    let hasBabylonCode = response.contains("BABYLON") || 
                        response.contains("createScene") ||
                        response.contains("```javascript") ||
                        response.contains("[INSERT_CODE]")
    
    if !hasBabylonCode {
        issues.append("Missing expected Babylon.js code patterns")
        isComplete = false
        shouldRetry = true
    }
    
    // Check for proper closure of code blocks
    if response.contains("[INSERT_CODE]") && !response.contains("[/INSERT_CODE]") {
        issues.append("Incomplete INSERT_CODE block")
        isComplete = false
        shouldRetry = true
    }
    
    if response.contains("```javascript") {
        let jsBlocks = response.components(separatedBy: "```javascript").count - 1
        let endBlocks = response.components(separatedBy: "```").count - 1 - jsBlocks
        if jsBlocks > endBlocks {
            issues.append("Unclosed code block")
            isComplete = false
            shouldRetry = true
        }
    }
    
    // Check for truncation indicators
    let truncationIndicators = ["...", "truncated", "incomplete", "cut off"]
    for indicator in truncationIndicators {
        if response.lowercased().contains(indicator.lowercased()) {
            issues.append("Contains truncation indicator: \(indicator)")
            isComplete = false
            shouldRetry = true
            break
        }
    }
    
    // Check if response ends abruptly (no proper sentence ending)
    let lastChars = String(response.suffix(10))
    if !lastChars.contains(".") && !lastChars.contains("!") && !lastChars.contains("?") && 
       !lastChars.contains("}") && !lastChars.contains("]") {
        issues.append("Response appears to end abruptly")
        isComplete = false
        shouldRetry = true
    }
    
    return ResponseValidation(isComplete: isComplete, shouldRetry: shouldRetry, issues: issues)
}

private func shouldRetryError(_ error: Error) -> Bool {
    let errorString = error.localizedDescription.lowercased()
    
    // OPTIMIZATION: More restrictive retry logic - only retry clear network/server issues
    // Don't retry client errors (400, 401, 403, 404) as they won't resolve with retry
    let networkErrors = ["timeout", "network", "connection failed"]
    let serverErrors = ["server error", "temporarily unavailable", "rate limit"]
    
    // Don't retry client errors that indicate API issues
    let clientErrors = ["400", "401", "403", "404", "invalid", "unauthorized", "forbidden"]
    
    // Check for client errors first - never retry these
    for clientError in clientErrors {
        if errorString.contains(clientError) {
            print("🚫 Client error detected, not retrying: \(clientError)")
            return false
        }
    }
    
    // Only retry clear network/server issues
    let shouldRetry = networkErrors.contains { errorString.contains($0) } ||
                     serverErrors.contains { errorString.contains($0) }
    
    print("📊 Retry decision for '\(errorString)': \(shouldRetry ? "RETRY" : "NO_RETRY")")
    return shouldRetry
}

// MARK: - Models

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let content: String
    let isUser: Bool
    let timestamp: Date
    let libraryId: String? // Track which 3D library was active when this message was created
}

enum ChatError: Error, LocalizedError {
    case sessionCreationFailed
    case invalidResponse
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed:
            return "Failed to create agent session"
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
