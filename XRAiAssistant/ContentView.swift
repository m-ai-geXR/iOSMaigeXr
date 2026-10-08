import SwiftUI
import WebKit
import Combine
import PhotosUI

enum AppView {
    case chat
    case scene
}

// MARK: - Keyboard Management
class KeyboardObserver: ObservableObject {
    @Published var isKeyboardVisible = false
    @Published var keyboardHeight: CGFloat = 0

    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { notification in
                (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            }
            .sink { frame in
                DispatchQueue.main.async {
                    self.keyboardHeight = frame.height
                    self.isKeyboardVisible = true
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { _ in
                DispatchQueue.main.async {
                    self.keyboardHeight = 0
                    self.isKeyboardVisible = false
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - m{ai}geXR Brand Component
struct MaigeXRBrandText: View {
    let isActive: Bool
    let fontSize: CGFloat

    init(isActive: Bool, fontSize: CGFloat = 10) {
        self.isActive = isActive
        self.fontSize = fontSize
    }

    var body: some View {
        HStack(spacing: 0) {
            // Brand rule: only {ai} takes the accent, the rest takes the
            // foreground. Both halves used accent colours before, which with a
            // single-accent palette rendered the whole wordmark one flat blue.
            Text("m")
                .foregroundColor(isActive ? .brandText : .brandMuted)
            Text("{ai}")
                .foregroundColor(isActive ? .brandAccentText : .brandMuted.opacity(0.7))
            Text("geXR")
                .foregroundColor(isActive ? .brandText : .brandMuted)
        }
        // Archivo is not a system face; default design at a heavy weight with
        // tight tracking is the closest match to the brand's Modernist setting.
        .font(.system(size: fontSize, weight: .heavy, design: .default))
        .tracking(-0.02 * fontSize)
    }
}

// MARK: - m{ai}geXR Avatar
/// The m{ai}geXR avatar (the GitHub org profile image), shown wherever the app
/// presents its own identity. Decorative: it always sits next to the name.
struct MaigeXRAvatar: View {
    var size: CGFloat = 24

    var body: some View {
        Image("MaigeXRAvatar")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

struct ContentView: View {
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var appearanceStore = AppearanceStore.shared
    @StateObject private var conversationStorage = ConversationStorageManager()
    @StateObject private var keyboardObserver = KeyboardObserver()
    @State private var webView: WKWebView?
    @State private var currentCode = ""
    @State private var lastGeneratedCode = ""
    /// Library the scene code was written for; code from another library is not replayed.
    @State private var lastCodeLibraryId = ""
    @State private var chatInput = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingExportSheet = false
    @State private var exportedFileURL: URL?
    @State private var currentView: AppView = .chat
    @State private var webViewReady = false
    @State private var isInjectingCode = false
    @State private var showingSettings = false
    @State private var settingsSaved = false
    @State private var showingExamples = false
    @State private var useSandpackForR3F = true // Toggle for Sandpack vs local playground
    @AppStorage(PlaygroundCommandLine.enabledKey) private var commandLineEnabled = true
    @State private var pendingCodeSandboxCode: String?
    @State private var pendingCodeSandboxFramework: String?
    @State private var codeSandboxCreateFunction: ((String) -> Void)?
    @State private var createdSandboxURL: String?  // URL of the created CodeSandbox for "Open Sandbox" button
    @State private var sandboxRecreationID = UUID()  // Change this to force CodeSandbox recreation

    // Image attachment support
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []

    // Modal picker states
    @State private var showingModelPicker = false

    // Screenshot tracking - only capture once per conversation
    @State private var screenshotCapturedForConversation: UUID? = nil

    /// True while either error surface is on screen.
    private func updateAdErrorVisibility() {
        AdManager.shared.setErrorVisible(showingError || chatViewModel.errorMessage != nil)
    }

    private var settingsView: some View {
        NavigationView {
            ScrollViewReader { proxy in
            Form {
                apiConfigurationSection
                localServerSection
                appearanceSection
                playgroundSection
                RemoveAdsSection()
                    .id("removeAds")
                aboutSection
                modelSettingsSection
                sandboxSettingsSection
                systemPromptSection
                saveSettingsSection
            }
            .onAppear {
                // Debug screenshots of the purchase for App Review.
                if DebugLaunch.screen == "removeads" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        proxy.scrollTo("removeAds", anchor: .top)
                    }
                }
            }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingSettings = false
                    }
                    .font(.system(size: 16, weight: .medium))
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        chatViewModel.saveSettings()
                        saveContentViewSettings()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            settingsSaved = true
                        }

                        // Auto-dismiss after showing confirmation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showingSettings = false
                                settingsSaved = false
                            }
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.neonPink)
                    .cornerRadius(8)
                    .neonButtonGlow(color: .neonPink)
                }
            }
        }
    }
    
    private var apiConfigurationSection: some View {
        Section {
            providerAPIKeyView(provider: "Together.ai", description: "Get a key at together.ai")
            providerAPIKeyView(provider: "OpenAI", description: "Get a key at platform.openai.com")
            providerAPIKeyView(provider: "Anthropic", description: "Get a key at console.anthropic.com")
            providerAPIKeyView(provider: "Google AI", description: "Get a key at aistudio.google.com/apikey")
            providerAPIKeyView(provider: "xAI", description: "Get a key at console.x.ai")
            codeSandboxAPIKeyView()
        } header: {
            Text("AI Provider API Keys")
        } footer: {
            Text("Keys stay on this device and are sent only to the provider they belong to.")
        }
    }

    /// The user's own model server (Ollama, LM Studio, any OpenAI-compatible
    /// server). Once an address and model are set, the model appears under
    /// "Local" in the model picker.
    private var localServerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Local server")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.brandText)
                    Spacer()
                    KeyStatusLabel(isSet: LocalServerConfig.isConfigured)
                }
                localServerField("Server address, e.g. http://192.168.1.20:11434", text: Binding(
                    get: { LocalServerConfig.baseURL },
                    set: { LocalServerConfig.baseURL = $0; chatViewModel.objectWillChange.send() }
                ))
                .keyboardType(.URL)
                localServerField("Model name, e.g. qwen2.5-coder:7b", text: Binding(
                    get: { LocalServerConfig.modelName },
                    set: { LocalServerConfig.modelName = $0; chatViewModel.objectWillChange.send() }
                ))
                SecureField("API key (optional)", text: Binding(
                    get: {
                        let key = chatViewModel.getAPIKey(for: LocalServerConfig.providerName)
                        return key == DEFAULT_API_KEY ? "" : key
                    },
                    set: { chatViewModel.setAPIKey(for: LocalServerConfig.providerName, key: $0) }
                ))
                .textContentType(.password)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.brandSurface))
            }
            .padding(.vertical, 6)
        } header: {
            Text("Local Model")
        } footer: {
            Text("Use a model running on your own computer or network, such as Ollama or LM Studio. Any server with an OpenAI-compatible API works. Pick it under Local in the model menu.")
        }
    }

    private func localServerField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.brandSurface))
    }

    /// One provider per row: name and status, the key field, where to get a key.
    /// The unset placeholder value shows as an empty field, not as masked dots.
    private func providerAPIKeyView(provider: String, description: String) -> some View {
        let configured = chatViewModel.isProviderConfigured(provider)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.brandText)
                Spacer()
                KeyStatusLabel(isSet: configured)
            }

            SecureField("Paste your \(provider) key", text: Binding(
                get: {
                    let key = chatViewModel.getAPIKey(for: provider)
                    return key == DEFAULT_API_KEY ? "" : key
                },
                set: { chatViewModel.setAPIKey(for: provider, key: $0) }
            ))
            .textContentType(.password)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.brandSurface))

            Text(description)
                .font(.caption)
                .foregroundColor(.brandMuted)
        }
        .padding(.vertical, 6)
    }

    private func codeSandboxAPIKeyView() -> some View {
        let key = chatViewModel.getAPIKey(for: "CodeSandbox")
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CodeSandbox")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.brandText)
                Text("Optional")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.brandMuted)
                Spacer()
                KeyStatusLabel(isSet: !key.isEmpty && key != DEFAULT_API_KEY)
            }

            SecureField("Paste your CodeSandbox key", text: Binding(
                get: { key == DEFAULT_API_KEY ? "" : key },
                set: { chatViewModel.setAPIKey(for: "CodeSandbox", key: $0) }
            ))
            .textContentType(.password)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.brandSurface))

            Text("React Three Fiber and Reactylon always use CodeSandbox. A key is optional and saves sandboxes to your account.")
                .font(.caption)
                .foregroundColor(.brandMuted)
        }
        .padding(.vertical, 6)
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearanceStore.appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text("System follows your device setting. The splash screen is always dark.")
                .font(.caption)
                .foregroundColor(.brandMuted)

            Picker("Chat style", selection: $appearanceStore.chatTheme) {
                ForEach(ChatTheme.allCases) { theme in
                    HStack(spacing: 8) {
                        HStack(spacing: 0) {
                            ForEach(Array(theme.swatch.enumerated()), id: \.offset) { _, color in
                                color.frame(width: 10, height: 18)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.brandDivider, lineWidth: 0.5))
                        Text(theme.displayName)
                    }
                    .tag(theme)
                }
            }
            .pickerStyle(.navigationLink)
        }
    }

    /// Legal links App Review expects to be reachable from inside the app.
    private var aboutSection: some View {
        Section("About") {
            Link(destination: AppConfig.privacyPolicyURL) {
                Label("Privacy policy", systemImage: "hand.raised")
            }
            .accessibilityHint("Opens in your browser")
        }
    }

    /// Playground options. The coordinator watches the same UserDefaults key, so the
    /// command line appears or disappears in the scene without a reload.
    private var playgroundSection: some View {
        Section("Playground") {
            Toggle(isOn: $commandLineEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scene command line")
                        .foregroundColor(.brandText)
                    Text("A one-line JavaScript console at the bottom of the scene. Run code against the live scene, type globals() to see what it exposes, Tab to complete, Esc to return to the scene.")
                        .font(.caption)
                        .foregroundColor(.brandMuted)
                }
            }
            .tint(.brandAccent)
        }
    }

    private var modelSettingsSection: some View {
        Section("Model & Library Settings") {
            VStack(alignment: .leading, spacing: 12) {
                modelSelectionView
                librarySelectionView
                if chatViewModel.usesEffortControl {
                    effortPickerView
                } else {
                    temperatureSliderView
                    topPSliderView
                }
                parameterSummaryView
            }
            .padding(.vertical, 4)
        }
    }
    
    private var modelSelectionView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI Model")
                .font(.headline)
                .foregroundColor(.primary)

            // Button to open modal picker
            Button(action: { showingModelPicker = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let currentModel = chatViewModel.allAvailableModels.first(where: { $0.id == chatViewModel.selectedModel }) {
                            Text(currentModel.displayName)
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(currentModel.provider)
                                .font(.caption)
                                .foregroundColor(.gray)
                        } else {
                            Text(chatViewModel.getModelDisplayName(chatViewModel.selectedModel))
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .sheet(isPresented: $showingModelPicker) {
                modelPickerSheet
            }
            
            // Show current provider info
            if let currentModel = chatViewModel.allAvailableModels.first(where: { $0.id == chatViewModel.selectedModel }) {
                HStack {
                    Image(systemName: "building.2")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Provider: \(currentModel.provider)")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    if chatViewModel.isProviderConfigured(currentModel.provider) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    private var librarySelectionView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("3D Library")
                .font(.headline)
                .foregroundColor(.primary)
            
            Picker("Library", selection: Binding(
                get: { chatViewModel.currentLibraryId },
                set: { newValue in
                    chatViewModel.selectLibrary(id: newValue)
                }
            )) {
                ForEach(chatViewModel.getAvailableLibraries(), id: \.id) { library in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(library.displayName)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text(library.version)
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                        }
                        Text(library.description)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .tag(library.id)
                }
            }
            .pickerStyle(MenuPickerStyle())
            
            // Show current library info
            let currentLibrary = chatViewModel.getCurrentLibrary()
            HStack {
                Image(systemName: "cube.box")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Library: \(currentLibrary.displayName)")
                    .font(.caption)
                    .foregroundColor(.green)
                
                Spacer()
                
                Text("Playground: \(currentLibrary.codeLanguage.rawValue)")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.top, 4)
        }
    }
    
    private var effortPickerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Reasoning Effort")
                    .font(.headline)
                    .foregroundColor(.cyberpunkWhite)
                Spacer()
                Text(chatViewModel.effort.displayName)
                    .font(.subheadline)
                    .foregroundColor(.neonBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.neonBlue.opacity(0.2))
                    .cornerRadius(6)
            }

            Picker("Reasoning Effort", selection: $chatViewModel.effort) {
                ForEach(AIEffort.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Text(chatViewModel.effort.summary)
                .font(.caption)
                .foregroundColor(.cyberpunkGray)

            Text("This model sets reasoning depth instead of temperature and top-p.")
                .font(.caption2)
                .foregroundColor(.cyberpunkGray)
        }
    }

    private var temperatureSliderView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Temperature")
                    .font(.headline)
                    .foregroundColor(.cyberpunkWhite)
                Spacer()
                Text("\(chatViewModel.temperature, specifier: "%.1f")")
                    .font(.subheadline)
                    .foregroundColor(.neonBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.neonBlue.opacity(0.2))
                    .cornerRadius(6)
            }

            Slider(value: $chatViewModel.temperature, in: 0.0...2.0, step: 0.1)
                .accentColor(.neonBlue)
                .neonCardGlow(color: .neonBlue)

            HStack {
                Text("0.0 - Focused")
                    .font(.caption)
                    .foregroundColor(.cyberpunkGray)
                Spacer()
                Text("2.0 - Creative")
                    .font(.caption)
                    .foregroundColor(.cyberpunkGray)
            }
        }
    }
    
    private var topPSliderView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Top-p (Nucleus Sampling)")
                    .font(.headline)
                    .foregroundColor(.cyberpunkWhite)
                Spacer()
                Text("\(chatViewModel.topP, specifier: "%.1f")")
                    .font(.subheadline)
                    .foregroundColor(.neonGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.neonGreen.opacity(0.2))
                    .cornerRadius(6)
            }

            Slider(value: $chatViewModel.topP, in: 0.1...1.0, step: 0.1)
                .accentColor(.neonGreen)
                .neonCardGlow(color: .neonGreen)

            HStack {
                Text("0.1 - Precise")
                    .font(.caption)
                    .foregroundColor(.cyberpunkGray)
                Spacer()
                Text("1.0 - Diverse")
                    .font(.caption)
                    .foregroundColor(.cyberpunkGray)
            }
            
            Text("Controls vocabulary diversity. Lower values focus on most likely words.")
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.top, 2)
        }
    }
    
    private var parameterSummaryView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "gauge.badge.plus")
                    .foregroundColor(.purple)
                    .font(.caption)
                Text("Current Mode")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Text(chatViewModel.getParameterDescription())
                .font(.subheadline)
                .foregroundColor(.purple)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
        }
    }

    private var sandboxSettingsSection: some View {
        Section("Sandbox & Deployment") {
            VStack(alignment: .leading, spacing: 8) {
                Label("React Three Fiber and Reactylon run on CodeSandbox", systemImage: "cloud.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text("These frameworks need an npm build, so their scenes are always built and shown on codesandbox.io. An internet connection is required. Babylon.js, Three.js, A-Frame and Nova64 run in the app.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 4)
        }
    }

    private var systemPromptSection: some View {
        Section("System Prompt") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Instructions")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                TextEditor(text: $chatViewModel.systemPrompt)
                    .frame(minHeight: 200)
                    .font(.system(size: 14).monospaced())
                    .padding(8)
                    .disableAutocorrection(true)
                    .autocapitalization(.none)
                    .textInputAutocapitalization(.never)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                Text("Customize how the AI assistant behaves and responds to your requests")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 4)
        }
    }
    
    private var saveSettingsSection: some View {
        Section {
            VStack(spacing: 12) {
                if settingsSaved {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Settings saved successfully!")
                            .font(.subheadline)
                            .foregroundColor(.green)
                        Spacer()
                    }
                    .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Save Your Settings")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        Text("Tap 'Save' to persist your API key, system prompt, model selection, and AI parameters. Your settings will be remembered when you return to the app.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            if currentView == .chat {
                chatView
            } else {
                sceneView
            }

            // Banner sits in the stack, above the tab bar, so it takes its own
            // space rather than covering the editor or the canvas. It renders
            // nothing at all for a paid user, so no gap is left behind.
            AdBannerView()

            // Bottom tab bar - always visible at bottom
            bottomTabBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom) // Let keyboard overlay instead of pushing
        // An ad must never land on a user waiting for a model, nor cover the
        // explanation of a failure. Forwarded from one place rather than
        // sprinkled through every request and error path.
        .onChange(of: chatViewModel.isLoading) { _, isLoading in
            if isLoading {
                AdManager.shared.generationBegan()
            } else {
                AdManager.shared.generationEnded()
            }
        }
        // Two independent error surfaces — the alert and the view model's
        // message. Both feed one computed answer, so whichever clears first
        // cannot declare the screen error-free while the other is still up.
        .onChange(of: chatViewModel.errorMessage) { _, _ in
            updateAdErrorVisibility()
        }
        .onChange(of: showingError) { _, _ in
            updateAdErrorVisibility()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingSettings) {
            settingsView
        }
        .sheet(isPresented: $showingExamples) {
            ExamplesView(library3DManager: chatViewModel.library3DManager) { example in
                // When user selects an example, inject the code
                currentView = .scene
                currentCode = example.code
                lastGeneratedCode = example.code
                lastCodeLibraryId = chatViewModel.getCurrentLibrary().id

                // Inject after a short delay to ensure view is loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    injectCodeWithRetry(example.code, maxRetries: 3)
                }
            }
        }
    }

    // MARK: - Model Picker Sheet
    private var modelPickerSheet: some View {
        NavigationView {
            List {
                // Show models organized by provider
                ForEach(Array(chatViewModel.modelsByProvider.keys.sorted()), id: \.self) { provider in
                    Section(header: Text(provider)) {
                        ForEach(chatViewModel.modelsByProvider[provider] ?? [], id: \.id) { model in
                            Button(action: {
                                chatViewModel.selectModel(model.id)
                                showingModelPicker = false
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(model.displayName)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text(model.description)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .lineLimit(2)
                                        if !model.pricing.isEmpty {
                                            Text(model.pricing)
                                                .font(.caption2)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    Spacer()
                                    if chatViewModel.selectedModel == model.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                            .font(.body)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                // Legacy models for backwards compatibility
                if !chatViewModel.availableModels.isEmpty {
                    Section(header: Text("Legacy (Together.ai)")) {
                        ForEach(chatViewModel.availableModels, id: \.self) { model in
                            Button(action: {
                                chatViewModel.selectModel(model)
                                showingModelPicker = false
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(chatViewModel.getModelDisplayName(model))
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text(chatViewModel.getModelDescription(model))
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if chatViewModel.selectedModel == model {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                            .font(.body)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .navigationTitle("Select AI Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingModelPicker = false
                    }
                }
            }
        }
    }

    // MARK: - Chat View
    private var chatView: some View {
        EnhancedChatView(
            viewModel: chatViewModel,
            storageManager: conversationStorage,
            onRunCode: { code, libraryId in
                print("🎯 Inline 'Run the Scene' button clicked with library: \(libraryId ?? "current")")

                // If libraryId is provided and different from current, switch to it temporarily
                if let targetLibraryId = libraryId, targetLibraryId != chatViewModel.currentLibraryId {
                    print("🔄 Switching from \(chatViewModel.currentLibraryId) to \(targetLibraryId) for this code")
                    chatViewModel.selectLibrary(id: targetLibraryId)
                }

                // Store code for use
                currentCode = code
                lastGeneratedCode = code
                lastCodeLibraryId = chatViewModel.getCurrentLibrary().id

                // ALWAYS use CodeSandbox for React Three Fiber
                let shouldUseCodeSandbox = chatViewModel.getCurrentLibrary().id == "reactThreeFiber"
                print("🔍 Inline button - Library: \(chatViewModel.getCurrentLibrary().id), useCodeSandbox: \(shouldUseCodeSandbox)")

                if shouldUseCodeSandbox {
                    print("🚀 Inline button: Using CodeSandbox for React Three Fiber")

                    // Store code and force view recreation (same as tab bar button)
                    pendingCodeSandboxCode = code
                    pendingCodeSandboxFramework = chatViewModel.getCurrentLibrary().id
                    sandboxRecreationID = UUID()
                    print("🔄 Inline button: Changed sandbox recreation ID to force new sandbox creation")

                    // Switch to scene view (will trigger CodeSandbox creation)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentView = .scene
                    }
                } else {
                    print("🚀 Inline button: Using local playground injection")

                    // Switch to scene view and inject code for local playgrounds
                    currentView = .scene

                    // Inject after a short delay to ensure view is loaded
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        injectCodeWithRetry(code, maxRetries: 3)
                    }
                }
            }
        )
    }
    
    // MARK: - Chat Header
    private var chatHeader: some View {
        VStack(spacing: 0) {
            // Top row with title and loading
            HStack {
                MaigeXRAvatar(size: 24)
                Text("AI Assistant")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if chatViewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Model and Library selector row
            HStack {
                                // Model selector
                                Image(systemName: "cpu")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                                
                                Text("Model:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Menu {
                                    // Show models organized by provider
                                    ForEach(Array(chatViewModel.modelsByProvider.keys.sorted()), id: \.self) { provider in
                                        Section(provider) {
                                            ForEach(chatViewModel.modelsByProvider[provider] ?? [], id: \.id) { model in
                                                Button(action: {
                                                    chatViewModel.selectModel(model.id)
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
                                                        
                                                        if chatViewModel.selectedModel == model.id {
                                                            Image(systemName: "checkmark")
                                                                .foregroundColor(.blue)
                                                                .font(.caption)
                                                        }
                                                        
                                                        if !chatViewModel.isProviderConfigured(provider) {
                                                            Image(systemName: "exclamationmark.triangle")
                                                                .foregroundColor(.orange)
                                                                .font(.caption2)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    
                                    // Legacy models
                                    if !chatViewModel.availableModels.isEmpty {
                                        Section("Legacy") {
                                            ForEach(chatViewModel.availableModels, id: \.self) { model in
                                                Button(action: {
                                                    chatViewModel.selectModel(model)
                                                }) {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        HStack {
                                                            Text(chatViewModel.getModelDisplayName(model))
                                                                .font(.system(size: 14, weight: .medium))
                                                            if chatViewModel.selectedModel == model {
                                                                Image(systemName: "checkmark")
                                                                    .foregroundColor(.blue)
                                                                    .font(.caption)
                                                            }
                                                        }
                                                        Text(chatViewModel.getModelDescription(model))
                                                            .font(.caption2)
                                                            .foregroundColor(.gray)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(chatViewModel.getModelDisplayName(chatViewModel.selectedModel))
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                                }
                                
                                // Library selector
                                Image(systemName: "cube.box")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                                    .padding(.leading, 12)
                                
                                Text("Library:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Menu {
                                    ForEach(chatViewModel.getAvailableLibraries(), id: \.id) { library in
                                        Button(action: {
                                            chatViewModel.selectLibrary(id: library.id)
                                        }) {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(library.displayName)
                                                        .font(.system(size: 14, weight: .medium))
                                                    Text(library.description)
                                                        .font(.caption2)
                                                        .foregroundColor(.gray)
                                                }
                                                
                                                Spacer()
                                                
                                                if chatViewModel.getCurrentLibrary().id == library.id {
                                                    Image(systemName: "checkmark")
                                                        .foregroundColor(.green)
                                                        .font(.caption)
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(chatViewModel.getCurrentLibrary().displayName)
                                            .font(.caption)
                                            .foregroundColor(.green)
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(6)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
        }
        .background(Color(.systemGray6))
    }
    
    // MARK: - Chat Messages
    private var chatMessages: some View {
        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(chatViewModel.messages) { message in
                                        ChatMessageView(message: message)
                                            .id(message.id)
                                    }
                                    
                                    if chatViewModel.isLoading {
                                        HStack {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                            Text("AI is thinking...")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground))
                            .onChange(of: chatViewModel.messages.count) { _ in
                                if let lastMessage = chatViewModel.messages.last {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
        }
    }
    
    // MARK: - Chat Code Banner
    private var chatCodeBanner: some View {
        Group {
            if !lastGeneratedCode.isEmpty {
                            VStack {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("AI code ready! Tap 'Run Scene' to see it.")
                                            .font(.callout)
                                            .foregroundColor(.green)
                                        Text("Generated by \(chatViewModel.getModelDisplayName(chatViewModel.selectedModel))")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    Text("(\(lastGeneratedCode.count) chars)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.1))
                                .overlay(
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundColor(.green.opacity(0.3)),
                                    alignment: .top
                                )
                            }
            }
        }
    }
    
    // MARK: - Chat Input
    private var chatInputView: some View {
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

            // Input row
            HStack(alignment: .bottom, spacing: 8) {
                // Image picker button
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 5, matching: .images) {
                    Image(systemName: selectedImages.isEmpty ? "photo.on.rectangle" : "photo.on.rectangle.fill")
                        .foregroundColor(selectedImages.isEmpty ? .gray : .blue)
                        .font(.system(size: 20))
                        .padding(8)
                }
                .onChange(of: selectedPhotos) { newItems in
                    Task {
                        await loadSelectedImages(from: newItems)
                    }
                }

                TextField("Ask me to create a 3D scene...", text: $chatInput, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .submitLabel(.send)
                    .onSubmit {
                        sendMessage()
                    }
                    .disableAutocorrection(true)
                    .keyboardType(.default)
                    .autocapitalization(.none)
                    .textInputAutocapitalization(.never)
                    .lineLimit(1...5)

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(8)
                        .background(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                        .clipShape(Circle())
                }
                .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
        }
    }
    
    // MARK: - Scene View
    private var sceneView: some View {
        VStack(spacing: 0) {
            ZStack {
                        // Check if we should use CodeSandbox for React Three Fiber or Reactylon
                        let currentLibraryId = chatViewModel.getCurrentLibrary().id
                        let _ = print("🔍 Scene View Check - useSandpackForR3F: \(useSandpackForR3F), currentLibraryId: \(currentLibraryId)")

                        // ALWAYS use CodeSandbox for React Three Fiber (ignore toggle for R3F)
                        if (currentLibraryId == "reactThreeFiber" || currentLibraryId == "reactylon") {
                            let _ = print("✅ Using CodeSandbox for \(currentLibraryId)")
                            CodeSandboxWebView(
                                webView: $webView,
                                framework: chatViewModel.getCurrentLibrary().id,
                                onWebViewLoaded: {
                                    print("✅ CodeSandbox WebView loaded successfully")

                                    // Check the current URL to determine what page we're on
                                    if let currentURL = self.webView?.url?.absoluteString {
                                        print("🔍 Current WebView URL: \(currentURL)")

                                        if currentURL.contains("codesandbox.io") && !currentURL.contains("/api/v1/sandboxes/define") {
                                            // We're on the actual CodeSandbox page - success!
                                            print("🎉 Successfully navigated to CodeSandbox!")
                                            print("✅ CodeSandbox integration complete")
                                            return
                                        }
                                    }

                                    // Check if we have pending CodeSandbox code to create
                                    if let pendingCode = pendingCodeSandboxCode,
                                       !pendingCode.isEmpty {
                                        print("🌐 Have pending CodeSandbox code: \(pendingCode.count) characters")
                                        print("🔍 Framework: \(pendingCodeSandboxFramework ?? "unknown")")

                                        // Wait a moment for WebView to be fully ready
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            print("🚀 Creating CodeSandbox using native API client")

                                            // Call the creation function provided by CodeSandboxWebView
                                            self.codeSandboxCreateFunction?(pendingCode)

                                            // Clear pending content
                                            self.pendingCodeSandboxCode = nil
                                            self.pendingCodeSandboxFramework = nil
                                        }
                                    } else {
                                        print("ℹ️ No pending CodeSandbox content to load")
                                    }
                                },
                                onWebViewError: { error in
                                    print("❌ CodeSandbox WebView error: \(error)")
                                    errorMessage = error.localizedDescription
                                    showingError = true
                                },
                                onSandboxCreated: { url in
                                    print("🎉 CodeSandbox created: \(url)")

                                    // Store the sandbox URL for "Open Sandbox" button
                                    DispatchQueue.main.async {
                                        self.createdSandboxURL = url
                                        print("✅ React Three Fiber scene deployed to CodeSandbox successfully!")
                                        print("🔗 Open sandbox URL: \(url)")
                                    }
                                },
                                onTriggerCreate: { createFunction in
                                    // Store the creation function for later use
                                    self.codeSandboxCreateFunction = createFunction
                                }
                            )
                            .id("\(chatViewModel.getCurrentLibrary().id)-\(sandboxRecreationID)")  // Force reload when library OR recreation ID changes
                        } else {
                            // Use traditional local playground for other frameworks
                            let _ = print("📝 Using local playground for \(currentLibraryId)")
                            PlaygroundWebView(
                                webView: $webView,
                                playgroundTemplate: chatViewModel.getPlaygroundTemplate(),
                                onWebViewLoaded: {
                                    print("Local playground WebView loaded successfully")
                                },
                                onWebViewError: { error in
                                    errorMessage = error.localizedDescription
                                    showingError = true
                                },
                                onJavaScriptMessage: { action, data in
                                    handleWebViewMessage(action: action, data: data)
                                }
                            )
                            .id(chatViewModel.getCurrentLibrary().id)  // Force reload when library changes
                        }
                        
                        // Code injection overlay
                        if isInjectingCode {
                            VStack {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.blue)
                                Text(chatViewModel.getCurrentLibrary().id == "reactThreeFiber" ?
                                    "Deploying to CodeSandbox..." : "Injecting AI Code...")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                    .padding(.top, 8)
                            }
                            .padding(20)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(12)
                        }

                        // Floating Screenshot Button (positioned to left, avoiding overlap)
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()

                                // Screenshot button - positioned left to avoid CodeSandbox button
                                Button(action: captureSceneScreenshot) {
                                    Image(systemName: "camera.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .frame(width: 48, height: 48)
                                        .glassEffect(
                                            tintColor: .cyberpunkDarkGray,
                                            opacity: 0.8,
                                            cornerRadius: 24,
                                            borderColor: .neonCyan
                                        )
                                }
                                
                                // Open Sandbox button - only show when CodeSandbox URL is available
                                if createdSandboxURL != nil {
                                    Button(action: openSandboxInBrowser) {
                                        Image(systemName: "arrow.up.right.square.fill")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                            .frame(width: 48, height: 48)
                                            .glassEffect(
                                                tintColor: .cyberpunkDarkGray,
                                                opacity: 0.8,
                                                cornerRadius: 24,
                                                borderColor: .neonPurple
                                            )
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.bottom, 80) // Increased bottom padding to position above bottom buttons
                        }

                    }
        }
    }


    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    // MARK: - Bottom Tab Bar
    private var bottomTabBar: some View {
        HStack {
                // Code Tab (Chat)
                Button(action: {
                    let leavingScene = currentView == .scene
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentView = .chat
                    }
                    // Interstitials only ever appear on the way out of a scene:
                    // the user has already seen the result they asked for. Wait
                    // out the transition so the ad does not present mid-animation.
                    if leavingScene {
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            await AdManager.shared.onSceneRun()
                        }
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: currentView == .chat ? "bubble.left.fill" : "bubble.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(currentView == .chat ? .brandAccentText : .brandMuted)
                        TabDot(isActive: currentView == .chat)
                    }
                    // Compact, but never below the 44pt minimum touch target.
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("m{ai}geXR chat")
                }
                                
                // Run Scene Tab
                Button(action: {
                    print("🎯 Run Scene button clicked (currentView: \(currentView == .scene ? "scene" : "chat"))")

                    // ALWAYS use CodeSandbox for React Three Fiber
                    let shouldUseCodeSandbox = chatViewModel.getCurrentLibrary().id == "reactThreeFiber"
                    print("🔍 Run Scene - Library: \(chatViewModel.getCurrentLibrary().id), useCodeSandbox: \(shouldUseCodeSandbox)")

                    if shouldUseCodeSandbox {
                        print("🚀 User clicked Run Scene for React Three Fiber (CodeSandbox mode)")

                        // Always store the latest code when clicking Run Scene
                        if !lastGeneratedCode.isEmpty {
                            pendingCodeSandboxCode = lastGeneratedCode
                            pendingCodeSandboxFramework = chatViewModel.getCurrentLibrary().id
                            print("✅ Stored code for CodeSandbox: \(lastGeneratedCode.count) characters")

                            // Force CodeSandbox view to recreate by changing its ID
                            // This ensures a NEW sandbox is created even if already on scene view
                            sandboxRecreationID = UUID()
                            print("🔄 Changed sandbox recreation ID to force new sandbox creation")
                        } else {
                            print("⚠️ No code to store for CodeSandbox")
                        }

                        // Switch to scene view (will trigger CodeSandbox creation with new ID)
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentView = .scene
                        }
                    } else if !lastGeneratedCode.isEmpty && lastCodeLibraryId == chatViewModel.getCurrentLibrary().id {
                        print("🚀 User clicked Run Scene for local playground")

                        // If already on scene view, just re-inject
                        if currentView == .scene {
                            print("🔄 Already on scene view - re-injecting code")
                            isInjectingCode = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.injectCodeWithRetry(lastGeneratedCode, maxRetries: 6)
                            }
                        } else {
                            // Switch to scene view first, then inject
                            print("🔄 Switching to scene view and injecting code")
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentView = .scene
                            }

                            isInjectingCode = true
                            // Wait longer for Scene tab to be visible and WebView to be ready
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                self.injectCodeWithRetry(lastGeneratedCode, maxRetries: 6)
                            }
                        }
                    } else if let demo = chatViewModel.library3DManager.welcomeExample {
                        // Nothing run yet: play the example the welcome message offers.
                        print("▶️ Nothing run yet - playing the welcome example: \(demo.title)")
                        currentCode = demo.code
                        lastGeneratedCode = demo.code
                        lastCodeLibraryId = chatViewModel.getCurrentLibrary().id
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentView = .scene
                        }
                        isInjectingCode = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.injectCodeWithRetry(demo.code, maxRetries: 6)
                        }
                    } else {
                        print("⚠️ No AI-generated code available, running default scene")
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentView = .scene
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.runScene()
                        }
                    }
                }) {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: currentView == .scene ? "play.circle.fill" : "play.circle")
                                .font(.system(size: 20, weight: .medium))

                            // New code waiting to run.
                            if !lastGeneratedCode.isEmpty && currentView != .scene {
                                Circle()
                                    .fill(Color.brandAccent)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 3, y: -1)
                            }
                        }
                        TabDot(isActive: currentView == .scene)
                    }
                    .foregroundColor(currentView == .scene ? .brandAccentText : .brandMuted)
                    // Compact, but never below the 44pt minimum touch target.
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Run scene")
                }
                
                // Examples Button
                Button(action: {
                    showingExamples = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "book")
                            .font(.system(size: 20, weight: .medium))
                        TabDot(isActive: false)
                    }
                    .foregroundColor(.brandMuted)
                    // Compact, but never below the 44pt minimum touch target.
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Examples")
                }

                // Settings Button
                Button(action: {
                    showingSettings = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .medium))
                        TabDot(isActive: false)
                    }
                    .foregroundColor(.brandMuted)
                    // Compact, but never below the 44pt minimum touch target.
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Settings")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .background(Color.brandBackground)
            .overlay(Hairline(), alignment: .top)
            .onChange(of: showingSettings) { isShowing in
            if !isShowing {
                settingsSaved = false
            }
        }
        .onAppear {
            setupChatCallbacks()
            loadContentViewSettings()
            switch DebugLaunch.screen {
            case "scene": currentView = .scene
            case "examples": showingExamples = true
            case "settings", "removeads": showingSettings = true
            default: break
            }
            #if DEBUG
            // Debug-only test hook: -maigeModel <id> -maigeAutoSend <text> sends a
            // message at launch, so leaving the app mid-reply can be tested.
            if let model = UserDefaults.standard.string(forKey: "maigeModel") {
                chatViewModel.selectModel(model)
            }
            if let text = UserDefaults.standard.string(forKey: "maigeAutoSend") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    chatViewModel.sendMessage(text, currentCode: nil)
                }
            }
            #endif
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Runs on CodeSandbox", isPresented: Binding(
            get: { chatViewModel.codeSandboxNotice != nil },
            set: { if !$0 { chatViewModel.codeSandboxNotice = nil } }
        )) {
            Button("OK", role: .cancel) { chatViewModel.codeSandboxNotice = nil }
        } message: {
            Text(chatViewModel.codeSandboxNotice ?? "")
        }
        .alert("Chat Error", isPresented: .constant(chatViewModel.errorMessage != nil)) {
            if chatViewModel.errorIsAboutKey {
                Button("Add \(chatViewModel.providerNameForSelectedModel) Key") {
                    chatViewModel.promptForKeyAfterError()
                }
            }
            Button(chatViewModel.errorIsAboutKey ? "Not Now" : "OK", role: .cancel) {
                chatViewModel.errorMessage = nil
            }
        } message: {
            Text(chatViewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showingExportSheet) {
            if let fileURL = exportedFileURL {
                ShareSheet(activityItems: [fileURL])
            }
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside text fields
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    
    private func setupChatCallbacks() {
        chatViewModel.onInsertCode = { code in
            print("=== CALLBACK: AI generated code received ===")
            print("Code length: \(code.count) characters")
            print("Code preview: \(code.prefix(200))...")
            lastGeneratedCode = code
            print("✅ Code stored successfully in lastGeneratedCode")
            
            // DO NOT inject here - wait for user to switch to Scene tab
            // The green banner will show "AI code ready! Tap 'Run Scene' to see it."
            print("Code ready - waiting for user to switch to Run Scene tab for injection and execution")
        }
        
        chatViewModel.onRunScene = {
            print("=== CALLBACK: onRunScene triggered - but disabled for manual execution ===")
            // DO NOT auto-switch or auto-run - let user manually control execution
            // The code is already stored via onInsertCode callback above
            // User must manually tap "Run Scene" tab to execute
        }
        
        chatViewModel.onDescribeScene = { description in
            print("Scene description: \(description)")
        }
        
        // Enhanced callback for build system
        chatViewModel.onInsertCodeWithBuild = { code, framework in
            print("=== ENHANCED CALLBACK: AI code with build support ===")
            print("Framework: \(framework.displayName)")
            print("Code length: \(code.count) characters")
            lastGeneratedCode = code
            
            // Auto-build for frameworks that require it
            if framework.requiresBuild {
                print("🏗️ Framework requires build - starting auto-build process")
                Task {
                    await self.buildAndRunCode(code: code, framework: framework)
                }
            } else {
                print("📝 Framework uses direct injection")
                // Standard injection flow
            }
        }
    }
    
    private func sendMessage() {
        let message = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        let messageCopy = message
        let imagesCopy = selectedImages

        // Clear input and images
        chatInput = ""
        selectedImages = []
        selectedPhotos = []

        // Dismiss keyboard immediately after sending
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        // Send message with images if present
        if !imagesCopy.isEmpty {
            chatViewModel.sendMessageWithImages(messageCopy, images: imagesCopy, currentCode: currentCode)
        } else {
            chatViewModel.sendMessage(messageCopy, currentCode: currentCode)
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
    
    private func handleWebViewMessage(action: String, data: [String: Any]) {
        switch action {
        case "initializationComplete":
            webViewReady = true
            print("WebView initialization complete - setting ready state")
            if let editorReady = data["editorReady"] as? Bool {
                print("Monaco editor ready: \(editorReady)")
            }
            if let engineReady = data["engineReady"] as? Bool {
                print("Babylon engine ready: \(engineReady)")
            }
        case "codeChanged":
            if let code = data["code"] as? String {
                currentCode = code
            }
        case "sceneCreated":
            print("Scene created successfully")
        case "sceneError":
            if let error = data["error"] as? String {
                errorMessage = "Scene Error: \(error)"
                showingError = true
            }
        case "codeRun":
            print("Scene execution completed")

            // Auto-capture screenshot after 5 seconds (like Android implementation)
            // Only capture once per conversation
            if let latestConversation = conversationStorage.conversations.first {
                if screenshotCapturedForConversation != latestConversation.id {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        print("📸 Auto-capturing screenshot 5 seconds after code execution...")
                        self.captureSceneScreenshotAuto()
                    }
                } else {
                    print("📸 Screenshot already captured for this conversation, skipping")
                }
            }
        case "codeInserted":
            if let code = data["code"] as? String {
                print("Code inserted: \(code)")
            }
        case "codeFormatted":
            print("Code formatted")
        case "consoleLog":
            if let level = data["level"] as? String,
               let message = data["message"] as? String {
                print("🌐 WebView Console [\(level.uppercased())]: \(message)")
                // Console messages now handled by floating console window in HTML
            }
        case "libraryStatusUpdate":
            if let libraries = data["libraries"] as? [String: Bool] {
                let context = data["context"] as? String ?? "unknown"
                print("📚 Library Status Update [\(context)]:")
                for (library, available) in libraries {
                    let status = available ? "✅" : "❌"
                    print("   \(status) \(library): \(available)")
                }
                
                // Check if all required libraries are loaded
                let requiredLibraries = ["React", "ReactDOM", "ReactThreeFiber", "THREE"]
                let allLoaded = requiredLibraries.allSatisfy { libraries[$0] == true }
                print("📊 All required libraries loaded: \(allLoaded ? "✅ YES" : "❌ NO")")
            }
        case "testInjection":
            print("🧪 Test injection requested")
            testEditorInjection()
        case "sceneExported":
            handleSceneExport(data: data)
        case "sceneSaved":
            handleSceneSave(data: data)
        default:
            print("Unknown action: \(action)")
        }
    }

    private func handleSceneExport(data: [String: Any]) {
        guard let format = data["format"] as? String,
              let filename = data["filename"] as? String,
              let base64Data = data["data"] as? String,
              let success = data["success"] as? Bool else {
            print("❌ Invalid scene export data")
            return
        }

        guard success else {
            print("❌ Scene export failed")
            return
        }

        print("📦 Received scene export: \(filename) (\(format))")

        // Decode base64 data
        guard let decodedData = Data(base64Encoded: base64Data) else {
            print("❌ Failed to decode base64 data")
            return
        }

        // Get documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)

        do {
            // Write file to documents directory
            try decodedData.write(to: fileURL)
            print("✅ Scene exported successfully to: \(fileURL.path)")

            // Get file size for logging
            let fileSize = (Double(decodedData.count) / 1024.0)
            print("📊 File size: \(String(format: "%.2f", fileSize)) KB")

            // Show share sheet to save/share the file
            DispatchQueue.main.async {
                self.exportedFileURL = fileURL
                self.showingExportSheet = true
            }
        } catch {
            print("❌ Failed to save export file: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.errorMessage = "❌ Export failed: \(error.localizedDescription)"
                self.showingError = true
            }
        }
    }

    private func handleSceneSave(data: [String: Any]) {
        guard let format = data["format"] as? String,
              let filename = data["filename"] as? String,
              let base64Data = data["data"] as? String,
              let success = data["success"] as? Bool else {
            print("❌ Invalid scene save data")
            return
        }

        guard success else {
            print("❌ Scene save failed")
            return
        }

        print("💾 Received scene package: \(filename) (\(format))")

        // Decode base64 data
        guard let decodedData = Data(base64Encoded: base64Data) else {
            print("❌ Failed to decode base64 data")
            return
        }

        // Get documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)

        do {
            // Write file to documents directory
            try decodedData.write(to: fileURL)
            print("✅ Scene package saved successfully to: \(fileURL.path)")

            // Get file size for logging
            let fileSize = (Double(decodedData.count) / 1024.0)
            print("📊 Package size: \(String(format: "%.2f", fileSize)) KB")

            // Show share sheet to save/share the .zip file
            DispatchQueue.main.async {
                self.exportedFileURL = fileURL
                self.showingExportSheet = true
            }
        } catch {
            print("❌ Failed to save scene package: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.errorMessage = "❌ Save failed: \(error.localizedDescription)"
                self.showingError = true
            }
        }
    }

    private func runScene() {
        guard let webView = webView else {
            errorMessage = "WebView not available"
            showingError = true
            return
        }

        let jsCode = "if (typeof runCode === 'function') { runCode(); } else { console.error('runCode function not found'); }"

        webView.evaluateJavaScript(jsCode) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Error running scene: \(error.localizedDescription)"
                    self.showingError = true
                }
                print("Error running scene: \(error?.localizedDescription ?? "unknown error")")
            }
        }
    }
    
    private func formatCode() {
        guard let webView = webView else {
            errorMessage = "WebView not available"
            showingError = true
            return
        }
        
        let jsCode = "if (typeof formatCode === 'function') { formatCode(); } else { console.error('formatCode function not found'); }"
        
        webView.evaluateJavaScript(jsCode) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Error formatting code: \(error.localizedDescription)"
                    self.showingError = true
                }
                print("Error formatting code: \(error?.localizedDescription ?? "unknown error")")
            }
        }
    }
    
    private func injectCodeWithRetry(_ code: String, maxRetries: Int) {
        print("🔄 Starting injection attempt with \(maxRetries) retries remaining...")
        
        guard let webView = webView else {
            print("❌ WebView not available for injection")
            isInjectingCode = false
            return
        }
        
        // Use different readiness checks based on Sandpack vs regular playground
        // ALWAYS use CodeSandbox for React Three Fiber
        let isUsingSandpack = chatViewModel.getCurrentLibrary().id == "reactThreeFiber"

        let checkReadinessJS: String

        if isUsingSandpack {
            // Sandpack readiness check - uses our new simple approach
            checkReadinessJS = """
            (function() {
                // Check if Sandpack environment is ready
                const sandpackReady = typeof window.isReady === 'function' && window.isReady();

                // Check if DOM is loaded
                const domReady = document.readyState === 'complete';

                // Check if injection function exists
                const injectionFuncReady = typeof window.setFullEditorContent === 'function';

                console.log('Sandpack readiness check:', {
                    sandpack: sandpackReady,
                    dom: domReady,
                    injection: injectionFuncReady
                });

                return sandpackReady && domReady && injectionFuncReady;
            })();
            """
        } else {
            // Legacy Monaco playground readiness check
            checkReadinessJS = """
            (function() {
                // Check Monaco editor readiness
                const monacoReady = window.editor &&
                                   typeof window.editor.setValue === 'function' &&
                                   typeof window.editor.getValue === 'function' &&
                                   typeof window.editor.layout === 'function';

                // Check editor ready flag (set by all playground templates)
                const editorFlagReady = window.editorReady === true;

                // Check if the DOM is fully loaded
                const domReady = document.readyState === 'complete';

                // Check if setFullEditorContent function exists (our injection function)
                const injectionFuncReady = typeof window.setFullEditorContent === 'function';

                console.log('Monaco readiness check:', {
                    monaco: monacoReady,
                    flag: editorFlagReady,
                    dom: domReady,
                    injection: injectionFuncReady
                });

                if (monacoReady && editorFlagReady && domReady) {
                    return "READY";
                } else {
                    return "NOT_READY";
                }
            })();
            """
        }
        
        webView.evaluateJavaScript(checkReadinessJS) { result, error in
            DispatchQueue.main.async {
                let isReady = isUsingSandpack ? (result as? Bool == true) : (result as? String == "READY")

                if isReady {
                    print("✅ \(isUsingSandpack ? "Sandpack" : "Monaco") editor is ready, proceeding with injection")
                    self.insertCodeInWebView(code)

                    // JavaScript function will handle auto-run, just clear the loading state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.isInjectingCode = false
                    }
                } else {
                    print("⏳ \(isUsingSandpack ? "Sandpack" : "Monaco") not ready yet, retries left: \(maxRetries)")
                    print("🔍 Current readiness result: \(result ?? "nil")")
                    if let error = error {
                        print("🔍 Readiness check error: \(error)")
                    }

                    if maxRetries > 0 {
                        // Retry after delay - longer delay for first few retries to allow full initialization
                        let delay = maxRetries > 3 ? 2.0 : 1.0
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.injectCodeWithRetry(code, maxRetries: maxRetries - 1)
                        }
                    } else {
                        print("❌ Max retries reached, injection failed")
                        print("🔍 Final check - trying emergency injection...")

                        // Emergency injection attempt - try even if not completely ready
                        self.insertCodeInWebView(code)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.isInjectingCode = false
                        }
                    }
                }
            }
        }
    }
    
    private func insertCodeInWebView(_ code: String) {
        guard let webView = webView else {
            print("❌ WebView not available")
            return
        }

        // Use JSON encoding for safer string escaping - prevents "Unexpected identifier" errors
        let jsonEncoder = JSONEncoder()
        let jsonString: String

        if let encoded = try? jsonEncoder.encode(code),
           let jsonStr = String(data: encoded, encoding: .utf8) {
            jsonString = jsonStr
        } else {
            // Fallback to manual escaping if JSON encoding fails
            jsonString = "\"\(code.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        }

        let jsCode = """
        console.log("=== CALLING ENHANCED setFullEditorContent ===");

        (function() {
            const codeToInject = \(jsonString);
            console.log("📋 Code length to inject:", codeToInject.length);

            // Try method 1: Enhanced setFullEditorContent function
            if (typeof setFullEditorContent === 'function') {
                console.log("📋 Method 1: Using setFullEditorContent function");
                try {
                    const success = setFullEditorContent(codeToInject);
                    console.log("setFullEditorContent result:", success ? "SUCCESS" : "FAILED");
                    if (success) return "SUCCESS_METHOD_1";
                } catch (error) {
                    console.error("❌ setFullEditorContent error:", error);
                    console.error("❌ Error details:", error.message, error.stack);
                }
            }

            // Try method 2: Direct Monaco setValue with checks
            if (window.editor && typeof window.editor.setValue === 'function') {
                console.log("📋 Method 2: Direct Monaco setValue");
                try {
                    window.editor.setValue(codeToInject);
                    if (typeof window.editor.layout === 'function') {
                        window.editor.layout();
                    }
                    if (typeof window.editor.focus === 'function') {
                        window.editor.focus();
                    }

                    // Try to trigger auto-run if available
                    if (typeof runCode === 'function') {
                        setTimeout(() => {
                            console.log("🚀 Auto-running code after injection...");
                            runCode();
                        }, 500);
                    }

                    console.log("✅ Direct injection completed");
                    return "SUCCESS_METHOD_2";
                } catch (error) {
                    console.error("❌ Direct injection error:", error);
                    console.error("❌ Error details:", error.message, error.stack);
                }
            }

            // Try method 3: Emergency text area injection (last resort)
            console.log("📋 Method 3: Emergency injection attempt");
            try {
                const editorElement = document.getElementById('monaco-editor');
                if (editorElement) {
                    console.log("Found editor element, attempting emergency injection");
                    // This is a fallback that at least puts the code somewhere visible
                    return "EMERGENCY_FALLBACK";
                }
            } catch (error) {
                console.error("❌ Emergency injection error:", error);
            }

            return "ALL_METHODS_FAILED";
        })();
        """
        
        print("Executing ENHANCED JavaScript code injection...")
        webView.evaluateJavaScript(jsCode) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ JavaScript execution error: \(error)")
                    // Don't show error immediately - the emergency injection might have worked
                    print("🔄 JavaScript error occurred, but continuing...")
                } else if let resultString = result as? String {
                    print("✅ JavaScript executed successfully")
                    print("📋 Injection result: \(resultString)")
                    
                    switch resultString {
                    case "SUCCESS_METHOD_1":
                        print("🎉 Code injection successful via setFullEditorContent")
                    case "SUCCESS_METHOD_2":
                        print("🎉 Code injection successful via direct Monaco API")
                    case "EMERGENCY_FALLBACK":
                        print("⚠️ Used emergency fallback injection method")
                    case "ALL_METHODS_FAILED":
                        print("❌ All injection methods failed")
                        self.errorMessage = "Unable to inject code into editor. Please try again."
                        self.showingError = true
                    default:
                        print("✅ Injection completed with result: \(resultString)")
                    }
                } else {
                    print("✅ JavaScript executed, result: \(String(describing: result))")
                }
            }
        }
    }
    
    // MARK: - Testing and Debugging
    
    /// Test function to verify Monaco editor injection system works across all playground templates
    private func testEditorInjection() {
        print("🧪 Testing editor injection system...")
        
        let testCode = """
        // Test injection - \(Date())
        console.log("Editor injection test successful!");
        """
        
        guard let webView = webView else {
            print("❌ WebView not available for testing")
            return
        }
        
        // Test the readiness check first
        let checkReadinessJS = """
        (function() {
            const monacoReady = window.editor && 
                               typeof window.editor.setValue === 'function' && 
                               typeof window.editor.getValue === 'function' &&
                               typeof window.editor.layout === 'function';
            
            const editorFlagReady = window.editorReady === true;
            const domReady = document.readyState === 'complete';
            const injectionFuncReady = typeof window.setFullEditorContent === 'function';
            
            return {
                monaco: monacoReady,
                flag: editorFlagReady, 
                dom: domReady,
                injection: injectionFuncReady,
                ready: monacoReady && editorFlagReady && domReady
            };
        })();
        """
        
        webView.evaluateJavaScript(checkReadinessJS) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("🧪 Test readiness check failed: \(error)")
                } else if let resultDict = result as? [String: Any] {
                    print("🧪 Test readiness results:")
                    for (key, value) in resultDict {
                        print("   \(key): \(value)")
                    }
                    
                    if let ready = resultDict["ready"] as? Bool, ready {
                        print("🧪 ✅ Editor is ready - proceeding with test injection")
                        self.insertCodeInWebView(testCode)
                    } else {
                        print("🧪 ❌ Editor not ready for testing")
                    }
                } else {
                    print("🧪 Test readiness check returned: \(String(describing: result))")
                }
            }
        }
    }
    
    private func buildAndRunCode(code: String, framework: FrameworkKind) async {
        print("🏗️ Building and running \(framework.displayName) code")

        // ALWAYS use CodeSandbox for React Three Fiber and Reactylon
        let shouldUseCodeSandbox = (
            chatViewModel.getCurrentLibrary().id == "reactThreeFiber" ||
            chatViewModel.getCurrentLibrary().id == "reactylon"
        )

        if shouldUseCodeSandbox {
            print("🌐 Using CodeSandbox for \(framework.displayName)")
            await handleCodeSandboxInjection(code: code, framework: framework)
            return
        }

        // Traditional build and injection for other frameworks
        await chatViewModel.buildSystem.buildCode(
            code: code,
            framework: framework
        ) { result in
            Task { @MainActor in
                if result.success {
                    print("✅ Build completed successfully")
                    if let bundleCode = result.bundleCode {
                        // Use the same injection mechanism that works for regular code
                        print("🔄 Injecting built bundle via working injection method...")
                        self.injectCodeWithRetry(bundleCode, maxRetries: 3)
                    }
                } else {
                    print("❌ Build failed: \(result.errors)")
                    self.errorMessage = "Build failed: \(result.errors.first ?? "Unknown error")"
                    self.showingError = true
                }
            }
        }
    }

    private func handleCodeSandboxInjection(code: String, framework: FrameworkKind) async {
        print("🌐 Creating CodeSandbox with user code using native API...")

        // Store the raw code - CodeSandboxWebView will use native API client
        await MainActor.run {
            print("🔍 User code length: \(code.count)")

            self.pendingCodeSandboxCode = code
            self.pendingCodeSandboxFramework = framework.rawValue
            print("✅ Stored code for native API CodeSandbox creation")

            // Force CodeSandbox view to recreate by changing its ID
            // This ensures a NEW sandbox is created (same as tab bar button)
            self.sandboxRecreationID = UUID()
            print("🔄 Changed sandbox recreation ID to force new sandbox creation")

            // Auto-switch to scene view to show the CodeSandbox
            print("🔄 Auto-switching to Scene tab to display CodeSandbox")
            withAnimation(.easeInOut(duration: 0.3)) {
                self.currentView = .scene
            }
        }

        // Wait a moment for the view to switch and CodeSandboxWebView to load
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        print("✅ Code ready for native API CodeSandbox creation")
    }

    
    private func injectBuiltCode(_ bundleCode: String, framework: FrameworkKind) {
        guard let webView = self.webView else {
            print("❌ WebView not available for bundle injection")
            return
        }
        
        print("🚀 Injecting built bundle for \(framework.displayName)")
        
        // For React Three Fiber, we need to execute the bundle directly
        let jsCode = bundleCode
        
        webView.evaluateJavaScript(jsCode) { result, error in
            if let error = error {
                print("❌ Bundle execution error: \(error)")
                Task { @MainActor in
                    self.errorMessage = "Bundle execution error: \(error.localizedDescription)"
                    self.showingError = true
                }
            } else {
                print("✅ Bundle executed successfully")
                Task { @MainActor in
                    // Auto-switch to scene view to show the result
                    self.currentView = .scene
                }
            }
        }
    }

    // MARK: - Settings Persistence

    private func saveContentViewSettings() {
        print("💾 Saving ContentView settings...")
        UserDefaults.standard.set(useSandpackForR3F, forKey: "XRAiAssistant_UseSandpackForR3F")
        print("✅ Sandpack setting saved: \(useSandpackForR3F)")
    }

    // MARK: - Screenshot Capture

    /// Captures a screenshot of the current 3D scene from the WebView
    private func captureSceneScreenshot() {
        guard let webView = webView else {
            print("⚠️ Cannot capture screenshot - WebView not available")
            return
        }

        print("📸 Capturing scene screenshot...")

        // Create a snapshot configuration
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: webView.bounds.size)

        // Take snapshot
        webView.takeSnapshot(with: config) { image, error in
            if let error = error {
                print("❌ Screenshot capture failed: \(error.localizedDescription)")
                return
            }

            guard let image = image else {
                print("❌ Screenshot capture returned nil image")
                return
            }

            print("✅ Screenshot captured successfully (\(Int(image.size.width))x\(Int(image.size.height)))")

            // Note: Screenshots are automatically saved to conversation history via captureSceneScreenshotAuto()
            // This manual screenshot is just for user reference
            print("💾 Screenshot captured (use auto-screenshot for conversation history)")
        }
    }

    /// Opens the CodeSandbox URL in the external browser
    private func openSandboxInBrowser() {
        guard let sandboxURL = createdSandboxURL,
              let url = URL(string: sandboxURL) else {
            print("⚠️ Cannot open sandbox - URL not available")
            return
        }

        print("🌐 Opening CodeSandbox in external browser: \(sandboxURL)")
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                print("✅ Successfully opened CodeSandbox in browser")
            } else {
                print("❌ Failed to open CodeSandbox in browser")
            }
        }
    }

    /// Automatically captures screenshot using JavaScript canvas.toDataURL (for conversation history)
    private func captureSceneScreenshotAuto() {
        guard let webView = webView else {
            print("⚠️ Cannot capture auto-screenshot - WebView not available")
            return
        }

        print("")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📸 AUTO-CAPTURING CANVAS SCREENSHOT")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let captureJS = """
        (function() {
            if (typeof captureCanvasScreenshot === 'function') {
                console.log("📸 Calling captureCanvasScreenshot...");
                return captureCanvasScreenshot();
            } else {
                console.error("❌ captureCanvasScreenshot function not found");
                return null;
            }
        })();
        """

        webView.evaluateJavaScript(captureJS) { result, error in
            if let error = error {
                print("❌ Auto-screenshot capture failed: \(error.localizedDescription)")
                return
            }

            guard let base64String = result as? String, !base64String.isEmpty else {
                print("❌ Auto-screenshot returned empty result")
                return
            }

            print("✅ Auto-screenshot captured: \(base64String.count) characters")

            // Save screenshot to current conversation (like Android implementation)
            // Find the most recent conversation (newly created or updated)
            if let latestConversation = self.conversationStorage.conversations.first {
                print("💾 Saving screenshot to conversation: \(latestConversation.id)")
                self.conversationStorage.updateConversationScreenshot(
                    conversationId: latestConversation.id,
                    screenshotBase64: base64String
                )

                // Mark this conversation as having a screenshot (one per conversation)
                self.screenshotCapturedForConversation = latestConversation.id
                print("✅ Screenshot flag set for conversation: \(latestConversation.id)")
            } else {
                print("⚠️ No conversations found - screenshot not saved")
            }

            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }
    }

    private func loadContentViewSettings() {
        print("📁 Loading ContentView settings...")

        // Check if the key exists - if not, default to true (CodeSandbox enabled)
        if UserDefaults.standard.object(forKey: "XRAiAssistant_UseSandpackForR3F") == nil {
            // First time - default to CodeSandbox enabled
            useSandpackForR3F = true
            UserDefaults.standard.set(true, forKey: "XRAiAssistant_UseSandpackForR3F")
            print("✅ First launch - CodeSandbox enabled by default")
        } else {
            // Load saved preference
            useSandpackForR3F = UserDefaults.standard.bool(forKey: "XRAiAssistant_UseSandpackForR3F")
            print("✅ Sandpack setting loaded: \(useSandpackForR3F)")
        }
    }

    // MARK: - CodeSandbox HTML Loading

    private func loadCodeSandboxHTMLInWebView(webView: WKWebView, html: String) {
        print("🔧 ContentView - Loading CodeSandbox HTML directly (new self-contained approach)")
        print("🔍 HTML content length: \(html.count)")

        // The HTML approach can be either:
        // 1. Self-contained with base64 encoded parameters (legacy)
        // 2. Direct API approach with fetch() calls (new)
        // Both handle submission internally via JavaScript

        let isLegacyBase64Approach = html.contains("base64Params") && html.contains("atob")
        let isDirectAPIApproach = html.contains("fetch(") && html.contains("codesandbox.io/api/v1/sandboxes/define")
        let isFormSubmissionApproach = html.contains("form.submit") && html.contains("codesandbox.io/api/v1/sandboxes/define")

        if isLegacyBase64Approach {
            print("✅ HTML contains self-contained base64 parameter handling")
            print("✅ Loading HTML directly - no parameter extraction needed")
            webView.loadHTMLString(html, baseURL: URL(string: "about:blank"))
        } else if isDirectAPIApproach {
            print("✅ HTML contains direct API approach with fetch()")
            print("✅ Loading HTML directly - will use fetch() to create sandbox")
            webView.loadHTMLString(html, baseURL: URL(string: "about:blank"))
        } else if isFormSubmissionApproach {
            print("✅ HTML contains form submission approach")
            print("✅ Loading HTML directly - will use form submission to create sandbox")
            webView.loadHTMLString(html, baseURL: URL(string: "about:blank"))
        } else {
            print("❌ HTML doesn't contain expected CodeSandbox integration")
            print("🔍 HTML snippet: \(String(html.prefix(500)))")
            loadCodeSandboxErrorPage(webView: webView)
        }
    }

    private func loadCodeSandboxErrorPage(webView: WKWebView) {
        let errorHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>CodeSandbox Error</title>
            <style>
                body {
                    font-family: system-ui, -apple-system, sans-serif;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    height: 100vh;
                    margin: 0;
                    background: #ff6b6b;
                    color: white;
                    text-align: center;
                    padding: 20px;
                }
            </style>
        </head>
        <body>
            <div>
                <h2>⚠️ CodeSandbox Creation Failed</h2>
                <p>Unable to create CodeSandbox due to parameter extraction error.</p>
                <p>Please try generating the code again.</p>
            </div>
        </body>
        </html>
        """

        webView.loadHTMLString(errorHTML, baseURL: URL(string: "about:blank"))
    }
}

struct ChatMessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: 250, alignment: .trailing)
                    
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: 250, alignment: .leading)
                    
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Share Sheet for iOS file sharing
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    ContentView()
}
/// "Configured" in the success colour, or a quiet "Not set".
private struct KeyStatusLabel: View {
    let isSet: Bool

    var body: some View {
        Label(isSet ? "Configured" : "Not set", systemImage: isSet ? "checkmark.circle.fill" : "circle.dashed")
            .font(.caption.weight(.medium))
            .foregroundColor(isSet ? .brandSuccess : .brandMuted)
    }
}

/// Marks the active tab now that tabs are icon-only: a small accent dot under
/// the icon. Takes the same space when inactive so icons never shift.
private struct TabDot: View {
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(isActive ? Color.brandAccentText : Color.clear)
            .frame(width: 4, height: 4)
            .accessibilityHidden(true)
    }
}
