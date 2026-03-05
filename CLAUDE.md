# CLAUDE.md - iOS m{ai}geXR

This file provides guidance to Claude Code (claude.ai/code) when working with the iOS implementation of m{ai}geXR.

**m{ai}geXR iOS** is an AI-powered Extended Reality development platform that combines Babylon.js, Together AI, React Three Fiber, and native iOS development into the ultimate mobile XR development environment with advanced AI assistance capabilities.

> **The Ultimate Mobile XR Development Environment for iOS**
> Democratizing 3D and Extended Reality development through conversational AI assistance, professional parameter control, and privacy-first architecture.

---

## 📝 COMMIT MESSAGE WORKFLOW

### Using COMMIT_MESSAGES.md

When making significant changes during a development session, Claude will:

1. **Document all changes** in `docs/COMMIT_MESSAGES.md`
2. **Write commit-ready messages** without quotes, backticks, or special formatting
3. **Include comprehensive details**: files changed, technical approach, testing notes
4. **Format for direct copy-paste** into git commit messages

### Workflow

**During Development:**
- Claude tracks all modifications throughout the session
- Documents patterns, fixes, and architectural decisions
- Notes files modified and line numbers

**End of Session:**
- User requests: "Please create commit message in docs/COMMIT_MESSAGES.md"
- Claude writes complete, formatted commit message
- User copies message directly from file to git commit

**Format Guidelines:**
- No quotation marks, backticks, or escaped characters
- Use standard markdown for readability
- Include technical details and rationale
- List all modified files with descriptions
- Document breaking changes and migration notes

**Example Request:**
```
Please create this document here docs/COMMIT_MESSAGES.md and articulate the current changes that have been made
```

---

## 🚨 CRITICAL FIXES (2025-11-22)

### Fix #1: Parameter Order Error ✅

**Issue**: SwiftCompile failed with "Argument 'maxTokens' must precede argument 'stream'"

**Root Cause**: The AIProxy library's `TogetherAIChatCompletionRequestBody` requires `maxTokens` parameter to come before `stream` parameter.

**Files Modified**:
- ✅ [XRAiAssistant/AIProviders/TogetherAIProvider.swift:88-95](XRAiAssistant/AIProviders/TogetherAIProvider.swift#L88-L95)
- ✅ [XRAiAssistant/ChatViewModel.swift:599-606](XRAiAssistant/ChatViewModel.swift#L599-L606)

**The Fix**:
```swift
// CORRECT parameter order
let requestBody = TogetherAIChatCompletionRequestBody(
    messages: togetherMessages,
    model: model,
    maxTokens: 4000,  // ✅ MUST come before stream
    stream: true,
    temperature: temperature,
    topP: topP
)
```

### Fix #2: Non-Serverless Model Error ✅

**Issue**: Together AI returned 400 error: "Unable to access non-serverless model Qwen/Qwen2.5-Coder-32B-Instruct"

**Root Cause**: The Qwen 2.5 Coder 32B model requires a dedicated endpoint and is not available as a serverless model on Together.ai.

**Files Modified**:
- ✅ [XRAiAssistant/ChatViewModel.swift:86-94](XRAiAssistant/ChatViewModel.swift#L86-L94)

**The Fix**: Removed `Qwen/Qwen2.5-Coder-32B-Instruct` from `availableModels` array. Only serverless models are now included:

```swift
let availableModels = [
    "deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free", // FREE
    "meta-llama/Llama-3.3-70B-Instruct-Turbo-Free",   // FREE
    "meta-llama/Meta-Llama-3-8B-Instruct-Lite",       // $0.10/1M
    "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo",    // $0.18/1M
    "Qwen/Qwen2.5-7B-Instruct-Turbo"                  // $0.30/1M
]
```

**User Action Required**: If you previously selected "Qwen 2.5 Coder 32B" in Settings, please switch to one of the FREE models:
- DeepSeek R1 70B (recommended for coding)
- Meta Llama 3.3 70B

**Why This Fixes 400 Errors**:
- Together AI API expects `max_tokens` parameter in requests
- AIProxy Swift library maps `maxTokens` to `max_tokens` in the JSON request
- Without this parameter, the API returns 400 Bad Request
- Setting it to 4000 matches the pattern used in AnthropicProvider (line 100)

**Verification**:
- Check logs for: `🔧 Together.ai config: stream=true, temperature=X, top-p=X, max-tokens=4000`
- API requests should now succeed with 200 OK responses
- Streaming responses will be properly received

---

## ⚙️ BUILD REQUIREMENTS - IMPORTANT

### **User Verifies Builds**

**IMPORTANT**: The user handles all build verification. Do NOT run `xcodebuild` commands unless explicitly requested.

- ✅ User will verify builds succeed
- ✅ User will check for compilation errors
- ✅ User will test on simulator/device
- ❌ Claude should NOT run build commands automatically

### **When to Suggest Build Verification**

After making ANY code changes, you MUST verify the project builds successfully:

```bash
# Quick build verification (REQUIRED)
xcodebuild -project XRAiAssistant.xcodeproj \
  -scheme XRAiAssistant \
  -configuration Debug \
  -sdk iphonesimulator \
  build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  2>&1 | grep -E "(error:|warning:|Build succeeded|BUILD FAILED)"
```

**Expected Output**: `** BUILD SUCCEEDED **`

**If Build Fails**:
1. Read the error messages carefully
2. Fix the errors (common: parameter order, missing imports, syntax errors)
3. Run build again
4. Repeat until build succeeds

**Common Build Issues**:
- Parameter order errors (e.g., `maxTokens` must precede `stream`)
- Missing package dependencies (resolve in Xcode)
- Corrupted DerivedData (clean: `rm -rf ~/Library/Developer/Xcode/DerivedData/XRAiAssistant-*`)

---

## 📱 iOS Project Structure

### Main Application (`m{ai}geXR/`)
```
m{ai}geXR/
├── m{ai}geXR.swift                  # App entry point
├── ContentView.swift                # Main UI with bottom navigation
├── ChatViewModel.swift              # AI integration + state management (LEGACY)
├── AIProviders/                     # NEW: Multi-provider system
│   ├── AIProvider.swift            # Protocol definitions
│   ├── AIProviderManager.swift     # Provider routing and management
│   ├── TogetherAIProvider.swift    # Together.ai implementation (FIXED ✅)
│   └── AnthropicProvider.swift     # Anthropic Claude implementation
├── Library3D/                       # 3D framework integrations
│   ├── Library3DManager.swift      # Framework selection
│   ├── BabylonJSLibrary.swift      # Babylon.js support
│   ├── ReactThreeFiberLibrary.swift # React Three Fiber support
│   └── ReactylonLibrary.swift      # Reactylon (React Babylon) support
├── BuildKit/                        # Advanced build system
│   ├── BuildManager.swift          # Orchestrates builds
│   ├── NodeBuildService.swift      # Node.js build environment
│   └── WasmBuildService.swift      # WebAssembly builds
├── SecureCodeSandboxService.swift   # CodeSandbox integration
└── Resources/                       # Assets and embedded HTML

m{ai}geXRTests/
├── ChatViewModelTests.swift         # AI integration tests
├── CodeSandboxIntegrationTests.swift # Sandbox tests
└── SecureCodeSandboxServiceTests.swift
```

### Key Dependencies

**iOS Native Stack**:
- **Swift 5.9+**: Modern language features and concurrency
- **SwiftUI**: Declarative UI framework
- **WebKit**: Web content integration
- **AIProxy Swift v0.129.0**: Together.ai + multi-provider API client
- **LlamaStackClient**: Meta Llama model integration

**Package Dependencies** ([Package.resolved](XRAiAssistant.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)):
- `AIProxySwift` v0.129.0 - AI provider client
- `llama-stack-client-swift` (main branch)
- Swift OpenAPI Generator stack (v1.10.3)

---

## 🤖 AI Provider System

### Architecture Overview

XRAiAssistant uses a **multi-provider architecture** that supports multiple AI services:

**Current Providers**:
1. **Together.ai** - Primary provider (FREE and paid models)
   - DeepSeek R1 70B (FREE)
   - Meta Llama 3.3 70B (FREE)
   - Qwen 2.5 7B Turbo ($0.30/1M tokens)

2. **Google AI (Gemini)** - NEW ✨ (FREE tier available)
   - Gemini 2.5 Flash (Fast, extended context)
   - Gemini 2.5 Pro (Advanced reasoning, 2M context)
   - Gemini 3.0 Flash Thinking (Explicit reasoning)
   - Gemini 1.5 Flash/Pro (Stable models)

3. **Anthropic Claude** - Advanced reasoning (UPDATED 2026-03-04) ✨
   - Claude Opus 4.6 (Latest - Most intelligent for agents & coding)
   - Claude Sonnet 4.6 (Best speed/intelligence combination)
   - Claude Haiku 4.5 (Fastest with near-frontier intelligence)
   - Legacy: Opus 4.5, Sonnet 4.5, Opus 4.1, Sonnet 4.0, Opus 4.0

4. **OpenAI** - GPT models (UPGRADED 2025-12-30) ✨
   - GPT-5.2 (Latest - Best for coding)
   - GPT-5.2 Pro (Highest accuracy)
   - GPT-5.2 Chat Latest (Auto-updating)
   - o1 (Advanced reasoning)
   - o3-mini (Enhanced reasoning)
   - GPT-4o, GPT-4o Mini (Legacy support)

5. **LlamaStack** - Fallback for Meta models
   - Direct Llama model access (when enabled)

### Provider Selection Logic

From [ChatViewModel.swift:403-435](XRAiAssistant/ChatViewModel.swift#L403-L435):

```swift
private func callLlamaInference(userMessage: String, systemPrompt: String) async throws -> String {
    // 1. Try new provider system first (better error handling)
    if let provider = aiProviderManager.getProvider(for: selectedModel) {
        return try await callNewProviderSystem(userMessage: userMessage, systemPrompt: systemPrompt)
    }

    // 2. Fall back to legacy routing
    if useLlamaStackForLlamaModels && selectedModel.contains("meta-llama") {
        return try await callLlamaStackModel(userMessage: userMessage, systemPrompt: systemPrompt)
    } else {
        return try await callTogetherAIModel(userMessage: userMessage, systemPrompt: systemPrompt)
    }
}
```

### Configuration

**API Key Management**:
- Default: `"changeMe"` - Users MUST configure their API key
- Location: Settings panel (gear icon in bottom navigation)
- Storage: UserDefaults with prefix `"XRAiAssistant_APIKey_<Provider>"`

**API Key Sources**:
- Together.ai: https://api.together.ai/settings/api-keys
- Google AI: https://aistudio.google.com/apikey (FREE tier available)
- Anthropic: https://console.anthropic.com
- OpenAI: https://platform.openai.com

**Model Parameters**:
- `temperature`: 0.0-2.0 (default: 0.7) - Controls randomness
- `topP`: 0.1-1.0 (default: 0.9) - Nucleus sampling
- `maxTokens`: 4000 - Maximum response length (REQUIRED)

---

## 🆕 Google AI (Gemini) Integration (2025-11-22)

### Overview

XRAiAssistant now supports Google's Gemini models through direct API integration!

**Files Added**:
- ✅ [XRAiAssistant/AIProviders/GoogleAIProvider.swift](XRAiAssistant/AIProviders/GoogleAIProvider.swift)

**Files Modified**:
- ✅ [XRAiAssistant/AIProviders/AIProviderManager.swift](XRAiAssistant/AIProviders/AIProviderManager.swift) - Added GoogleAIProvider
- ✅ [XRAiAssistant/ContentView.swift](XRAiAssistant/ContentView.swift) - Added Google AI API key field

### Available Gemini Models

**Gemini 2.5 Series** (Latest Stable):
- `gemini-2.5-flash` - Fast model with improved performance and extended context (DEFAULT)
- `gemini-2.5-pro` - Most capable with advanced reasoning (1M token context)
- `gemini-2.5-flash-lite` - Fast, low-cost, high-performance model

**Gemini 3 Series** (Preview - Thinking Mode):
- `gemini-3-pro-preview` - Advanced reasoning with thinking mode

**Gemini 2.0 Series** (Stable):
- `gemini-2.0-flash` - Next-gen features with 1M token context

### API Configuration

**Endpoint**: `https://generativelanguage.googleapis.com/v1beta`
**Method**: POST with streaming via SSE (Server-Sent Events)
**Authentication**: API key passed as query parameter

**Get Your Free API Key**:
1. Visit https://aistudio.google.com/apikey
2. Sign in with your Google account
3. Create a new API key
4. Paste into Settings → Google AI API Key field

**Request Format**:
```swift
{
    "contents": [
        {"role": "user", "parts": [{"text": "message"}]}
    ],
    "generationConfig": {
        "temperature": 0.7,
        "topP": 0.9,
        "maxOutputTokens": 4000
    },
    "systemInstruction": {
        "parts": [{"text": "system prompt"}]
    }
}
```

**Response Format** (SSE):
```
data: {"candidates":[{"content":{"parts":[{"text":"response"}]}}]}
```

### Features

- ✅ Streaming support via Server-Sent Events
- ✅ System instructions (separate from conversation)
- ✅ Temperature and Top-P control
- ✅ Extended context windows (up to 2M tokens for Pro)
- ✅ Free tier available with generous quotas
- ✅ Thinking mode support (Gemini 3.0)

### Pricing

All Gemini models offer a **FREE tier** with generous daily quotas:
- Flash models: High free quota
- Pro models: Moderate free quota
- Paid tier available for production use

See: https://ai.google.dev/pricing

---

## 🆕 OpenAI GPT-5.2 Integration (2025-12-30)

### Overview

XRAiAssistant now supports OpenAI's latest GPT-5.2 models, matching feature parity with the Android implementation!

**Files Modified**:
- ✅ [XRAiAssistant/AIProviders/OpenAIProvider.swift](XRAiAssistant/AIProviders/OpenAIProvider.swift)

### Available GPT Models

**GPT-5.2 Series** (Latest - December 2025):
- `gpt-5.2` - Best model for coding and agentic tasks (DEFAULT)
- `gpt-5.2-pro` - Smartest and most trustworthy with highest accuracy
- `gpt-5.2-chat-latest` - Latest ChatGPT model with automatic updates

**Reasoning Models** (o-series):
- `o1-2024-12-17` - Advanced reasoning model for complex problems
- `o3-mini-2025-01-31` - Latest reasoning model with enhanced reasoning abilities

**GPT-4o Series** (Legacy Support):
- `gpt-4o` - Versatile high-intelligence flagship model
- `gpt-4o-mini` - Fast and affordable small model for focused tasks

**Removed Legacy Models**:
- ❌ GPT-4 Turbo (replaced by GPT-5.2)
- ❌ GPT-3.5 Turbo (replaced by GPT-4o Mini)

### API Configuration

**Endpoint**: `https://api.openai.com/v1/chat/completions`
**Method**: POST with streaming
**Authentication**: Bearer token in Authorization header

**Get Your API Key**:
1. Visit https://platform.openai.com
2. Sign in or create account
3. Navigate to API keys section
4. Create new secret key
5. Paste into Settings → OpenAI API Key field

**Request Format**:
```swift
{
    "model": "gpt-5.2",
    "messages": [
        {"role": "system", "content": "system prompt"},
        {"role": "user", "content": "message"}
    ],
    "temperature": 0.7,
    "top_p": 0.9,
    "stream": true
}
```

**Response Format** (SSE):
```
data: {"choices":[{"delta":{"content":"response chunk"}}]}
data: [DONE]
```

### Features

- ✅ Streaming support via Server-Sent Events
- ✅ Vision support for GPT-5.2 and GPT-4o models (multimodal)
- ✅ Temperature and Top-P control
- ✅ Extended context windows (up to 400K tokens for GPT-5.2)
- ✅ Advanced reasoning capabilities (o1, o3-mini)
- ✅ Function calling support (all models)

### Pricing

**GPT-5.2 Series**:
- GPT-5.2: $1.75/$14.00 per 1M tokens (input/output)
- GPT-5.2 Pro: Premium tier pricing
- GPT-5.2 Chat Latest: $1.75/$14.00 per 1M tokens

**Reasoning Models**:
- o1: Premium tier pricing
- o3-mini: Economy tier pricing

**GPT-4o Series**:
- GPT-4o: $2.50/$10.00 per 1M tokens
- GPT-4o Mini: $0.15/$0.60 per 1M tokens

See: https://openai.com/pricing

### Upgrade Summary

**iOS Implementation Now Matches Android**:
- ✅ 7 OpenAI models (same as Android)
- ✅ Latest GPT-5.2 generation included
- ✅ Reasoning models (o1, o3-mini) included
- ✅ 400K token context window
- ✅ Vision support for multimodal models
- ✅ Same pricing structure

**Upgraded From**:
- 4 models → 7 models
- 128K context → 400K context
- GPT-4o max → GPT-5.2 max

---

## 🌐 3D Framework Support

### Supported Frameworks

1. **Babylon.js** - Full-featured 3D engine
   - Native WebGL rendering
   - Advanced lighting and materials
   - Physics engine support

2. **React Three Fiber** - React wrapper for Three.js
   - Component-based 3D scenes
   - JSX syntax for 3D objects
   - Hooks for animations

3. **Reactylon** - React wrapper for Babylon.js
   - React components with Babylon.js power
   - Declarative 3D scene definition

4. **Three.js** - Direct Three.js integration
   - Low-level 3D control
   - Custom shaders and effects

5. **A-Frame** - Entity-component system
   - HTML-based 3D scenes
   - WebXR support

### Framework Manager

The [Library3DManager](XRAiAssistant/Library3D/Library3DManager.swift) orchestrates:
- Framework selection and switching
- Library-specific AI prompts
- Code generation templates
- Example scenes

---

## 🔧 Build System (BuildKit)

### Overview

Advanced build system supporting:
- **Node.js builds** - npm/webpack bundling
- **WebAssembly builds** - Rust/C++ compilation
- **Hot reload** - Live code updates
- **Build analysis** - Performance metrics

### Build Manager

From [BuildManager.swift](XRAiAssistant/BuildKit/BuildManager.swift):

```swift
class BuildManager {
    func buildProject(code: String, framework: FrameworkKind) async throws -> BuildResult {
        // Route to appropriate build service
        switch framework {
        case .node:
            return try await nodeBuildService.build(code: code)
        case .wasm:
            return try await wasmBuildService.build(code: code)
        }
    }
}
```

**Supported Build Types**:
- React Three Fiber → Node.js build
- Reactylon → Node.js build
- Custom frameworks → WASM build

---

## 🎯 CodeSandbox Integration

### Secure Sandbox Service

The [SecureCodeSandboxService](XRAiAssistant/SecureCodeSandboxService.swift) provides:
- **Secure code execution** - Isolated sandbox environment
- **Live preview** - Real-time 3D rendering
- **Shareable URLs** - Deploy and share creations
- **Version control** - Save and restore projects

### API Integration

**Endpoint**: `https://codesandbox.io/api/v1/sandboxes/define`
**Method**: POST with JSON body containing files structure

**Example Request**:
```swift
let files: [String: CodeSandboxFile] = [
    "package.json": CodeSandboxFile(content: packageJSON),
    "src/index.js": CodeSandboxFile(content: jsCode),
    "src/App.js": CodeSandboxFile(content: appCode)
]

let sandboxURL = try await createSandbox(files: files)
```

---

## 🔐 Security & Privacy

### API Key Security
- ✅ Default value: `"changeMe"` prevents accidental exposure
- ✅ User-configured keys stored in UserDefaults
- ✅ Key validation before API calls
- ✅ Helpful error messages for missing/invalid keys

### Privacy-First Architecture
- ✅ All user data stays on-device
- ✅ No analytics or tracking
- ✅ Generated code remains private
- ✅ Optional cloud deployment (user-initiated)

---

## ⚙️ Settings Persistence

### UserDefaults Keys

All settings use the `"XRAiAssistant_"` prefix:

```swift
// API Configuration
UserDefaults.standard.set(apiKey, forKey: "XRAiAssistant_APIKey")
UserDefaults.standard.set(selectedModel, forKey: "XRAiAssistant_SelectedModel")

// AI Parameters
UserDefaults.standard.set(temperature, forKey: "XRAiAssistant_Temperature")
UserDefaults.standard.set(topP, forKey: "XRAiAssistant_TopP")

// System Prompts
UserDefaults.standard.set(systemPrompt, forKey: "XRAiAssistant_SystemPrompt")
```

### Auto-Restore on Launch

From [ChatViewModel.swift:150](XRAiAssistant/ChatViewModel.swift#L150):

```swift
init() {
    // ... initialization ...
    loadSettings()  // Auto-restore all user preferences
}
```

---

## 🧪 Testing

### Test Coverage

**Unit Tests**:
- [ChatViewModelTests.swift](m{ai}geXRTests/ChatViewModelTests.swift) - AI integration tests
- SecureCodeSandboxServiceTests.swift - Sandbox API tests

**Integration Tests**:
- CodeSandboxIntegrationTests.swift - Full E2E workflow
- CodeSandboxCompleteIntegrationTests.swift - Production scenarios

### Running Tests

```bash
# Build and test
xcodebuild test \
  -project m{ai}geXR.xcodeproj \
  -scheme m{ai}geXR \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M3)'
```

---

## 🚀 Development Guidelines

### Code Standards
- **Swift Style**: SwiftUI best practices, use `@Published` for reactive properties
- **AI Integration**: Always include error handling and retry logic
- **Logging**: Use emoji prefixes for visual categorization (`🚀`, `✅`, `❌`, `⚠️`)
- **Performance**: Optimize for mobile constraints (memory, battery, network)

### AI Parameter Tuning

```swift
enum AIMode {
    case debugging    // temp: 0.2, top-p: 0.3 - Highly focused
    case balanced     // temp: 0.7, top-p: 0.9 - General purpose (DEFAULT)
    case creative     // temp: 1.2, top-p: 0.9 - Maximum innovation
    case teaching     // temp: 0.7, top-p: 0.8 - Educational explanations
}
```

### Error Handling

From [ChatViewModel.swift:368-386](XRAiAssistant/ChatViewModel.swift#L368-L386):

```swift
catch {
    if let providerError = error as? AIProviderError {
        switch providerError {
        case .configurationError(let message):
            if message.contains("API key not configured") {
                errorMessage = "⚠️ API Key Required: Please configure your Together.ai API key in Settings"
            }
        }
    } else if error.localizedDescription.contains("401") {
        errorMessage = "⚠️ Authentication Failed: Please verify your API key in Settings"
    }
}
```

**Best Practices**:
- Provide user-friendly error messages
- Include actionable next steps
- Link to API key settings
- Log technical details for debugging

---

## 📦 Build Requirements

### Build Verification (MANDATORY)

At the end of EVERY coding session, verify the project builds:

```bash
# Quick build check (no code signing)
xcodebuild -project m{ai}geXR.xcodeproj \
  -scheme m{ai}geXR \
  -configuration Debug \
  -sdk iphonesimulator \
  build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  2>&1 | grep -E "(error:|warning:|Build succeeded|BUILD FAILED)"
```

**Expected Output**: `** BUILD SUCCEEDED **`

### Xcode 15+ File Synchronization

**IMPORTANT**: This project uses Xcode 15+ automatic file system synchronization.

- ✅ New Swift files are automatically included when placed in directories
- ✅ No manual `.pbxproj` editing required
- ❌ DO NOT programmatically modify `project.pbxproj` (causes corruption)

**Recovery from Corruption**:
```bash
# If you see "duplicate GUID" errors:
./scripts/xcode_recovery.sh

# Then open Xcode to resolve packages
open m{ai}geXR.xcodeproj
```

---

## 🎯 Current State (2025-11-22)

### ✅ Fully Implemented
- Multi-provider AI system (Together.ai, Anthropic, LlamaStack)
- Professional parameter control (temperature, top-p, max-tokens)
- Settings persistence with auto-restore
- Multiple 3D framework support (5 frameworks)
- CodeSandbox integration for sharing
- Advanced build system with hot reload
- Comprehensive error handling
- **Together AI API 400 errors FIXED** ✅

### 🚧 In Development
- Local SQLite RAG system for offline knowledge
- Multi-modal AI (image input for scene analysis)
- Extended model support (more providers)

### 📋 Roadmap
- Android version feature parity
- Desktop (macOS/Windows) deployment
- Community example library
- Collaborative features

---

## 🐛 Common Issues & Solutions

### Issue: 400 Bad Request from Together AI
**Solution**: ✅ FIXED - Added `maxTokens: 4000` parameter to all Together.ai requests

### Issue: API Key Not Configured
**Solution**:
1. Tap Settings (gear icon) in bottom navigation
2. Replace "changeMe" with your Together.ai API key
3. Get free API key at https://api.together.ai/settings/api-keys

### Issue: Empty AI Responses
**Solution**: Check that `maxTokens` is set (now default 4000)

### Issue: Build Failures
**Solution**:
1. Clean DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData`
2. Resolve Swift packages in Xcode
3. Rebuild project

---

## 📚 Additional Resources

### Documentation
- [MultiProviderSetup.md](XRAiAssistant/Documentation/MultiProviderSetup.md) - AI provider configuration
- [BugFixes.md](XRAiAssistant/Documentation/BugFixes.md) - Historical fixes
- [README.md](README.md) - Project overview

### External Links
- Together AI Docs: https://docs.together.ai
- AIProxy Swift: https://github.com/lzell/AIProxySwift
- Babylon.js: https://www.babylonjs.com
- React Three Fiber: https://docs.pmnd.rs/react-three-fiber

---

## 🔄 Version History

**2025-11-22**: Fixed Together AI 400 errors by adding `maxTokens` parameter
**2025-10-15**: Implemented Reactylon API fixes and camera setup patterns
**2025-10-14**: Added React Three Fiber CodeSandbox integration

---

**m{ai}geXR iOS** - The future of AI-powered XR development 🚀
