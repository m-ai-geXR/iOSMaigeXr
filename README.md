# m{ai}geXR iOS

**AI-powered 3D and Extended Reality development, on iPhone and iPad.**

Describe a scene in plain English; m{ai}geXR writes the code for your chosen 3D
framework, runs it in an embedded playground, and keeps editing it as you keep
talking.

SwiftUI client bridged to a WebKit playground, sharing its model catalog, 3D
library set and system prompts with the Android (`AndroidMaigeXr/`) and desktop
(`WebMaigeXr/`) clients.

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-18.0+-blue.svg)](https://developer.apple.com/ios/)
![License](https://img.shields.io/badge/License-MIT-green.svg)
[![Sponsor seacloud9](https://img.shields.io/badge/Sponsor-seacloud9-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/seacloud9)

**iOS 18.0+** · Swift 5.9+ · requires a Mac with Xcode

---

## Features

### Multi-provider AI

Five providers, each with its own client under
[XRAiAssistant/AIProviders/](XRAiAssistant/AIProviders/):

| Provider | Models |
|---|---|
| **Together.ai** | DeepSeek R1 70B (free), Llama 3.3 70B (free), Llama 3 8B Lite, Llama 3.1 8B Turbo, Qwen 2.5 7B Turbo |
| **OpenAI** | GPT-6 Astra, GPT-5.6 Sol / Terra / Luna, GPT-5.2 |
| **Anthropic** | Claude Fable 5.1, Opus 5, Sonnet 5, Haiku 4.5, Opus 4.6, Sonnet 4.6 |
| **Google AI** | Gemini 3.1 Pro, Gemini 2.5 Pro / Flash / Flash Lite |
| **xAI** | Grok 4, Grok 4 Fast Reasoning, Grok 3, Grok 3 Mini, Grok Code Fast |

**Two control modes.** The frontier models (Claude 5 series, GPT-5.6 / GPT-6)
removed `temperature` and `top_p` and reject requests carrying them, so they
take a discrete **Reasoning Effort** level instead — `low`, `medium`, `high`,
`xhigh` or `max`. Every other model keeps **Temperature** (0.0–2.0) and
**Top-p** (0.1–1.0). Settings shows whichever applies to the selected model.

Responses stream. Transient stream drops are retried in the OpenAI and
Anthropic providers, timeouts are raised for reasoning models, and
provider-owned models are no longer misrouted to the Together.ai fallback.

### Six 3D libraries

Registered in
[Library3D/Library3D.swift](XRAiAssistant/Library3D/Library3D.swift)
(`Library3DFactory`), each with its own system prompt and starter template:

| Library | How it runs |
|---|---|
| **Babylon.js** | CDN injection into the WebKit playground — the default |
| **Three.js** | Direct injection |
| **A-Frame** | CDN injection, WebXR VR/AR |
| **React Three Fiber** | Sandpack / CodeSandbox build step |
| **Reactylon** | Sandpack / CodeSandbox build step |
| **Nova64** | Embedded studio runner — see below |

**Nova64** is a retro 3D fantasy console (N64/PS1-era low-poly rendering on top
of Three.js), not a library you call. It boots its own runtime and accepts
*carts*, so the playground embeds Nova64's hosted runner and pushes the editor
buffer into it over `postMessage`. Two constraints shape it:

- **Carts must not use `export`.** The runner evaluates source with
  `new Function()` and then looks up `init` / `update` / `draw` by name, so a
  top-level `export` is a syntax error. The system prompt says so emphatically.
- **The host page needs a real origin.** Loading the playground from `file://`
  gives it an opaque origin and the runner throws before the cart runs, so the
  WebView loads it from an `https` base URL instead.

Cross-platform design notes live in the desktop repository at
`WebMaigeXr/docs/NOVA64_INTEGRATION.md`.

### Development environment

- **Monaco editor** in a WebKit playground with a Swift ↔ JavaScript bridge
- **Conversation history** with threaded messages and reply indicators
- **Favorites** for scenes worth keeping
- **Examples** browser with ready-made scenes per framework
- **Markdown rendering** of AI responses
- **Vaporwave splash screen** (`Resources/splash.html`), visually matched to the
  Android and desktop clients
- **BuildKit** and a bundled **NodeWorker** for the frameworks that need a
  build step

### Privacy-first RAG

A local GRDB/SQLite database plus a vector search service and embedding service
provide on-device retrieval over your own scene history
([XRAiAssistant/RAG/](XRAiAssistant/RAG/),
[XRAiAssistant/Database/](XRAiAssistant/Database/)). Nothing leaves the device
except the request you send to your chosen AI provider.

API keys default to `changeMe` and are configured in Settings — see setup below.

---

## Getting started

### Prerequisites

- **macOS with Xcode** (iOS 18 SDK)
- **CocoaPods**, for the ad SDKs

### Build and run

```bash
cd iOSMaigeXr
pod install
open XRAiAssistant.xcodeproj
```

Pick a simulator or device and press **▶ Run**.

Swift Package Manager resolves the rest automatically: AIProxySwift,
LlamaStackClient, GRDB.swift, and the Google Mobile Ads SPM package. CocoaPods
supplies Google Mobile Ads, Unity Ads and the Google User Messaging Platform
(GDPR consent); the Podfile pins pods to a 16.0 deployment target while the app
target is 18.0.

> To run on a physical iPhone rather than a simulator, Xcode will ask you to
> sign in with an Apple ID. A free account is fine.

### Configure a provider

m{ai}geXR ships with `apiKey = "changeMe"` and no key of its own. **AI features
do nothing until you set one.**

1. Launch the app
2. Tap **Settings** (gear icon) in the bottom tab bar
3. Replace `changeMe` with a key for the provider you want:
   - **Google AI** — [aistudio.google.com/apikey](https://aistudio.google.com/apikey) (free tier, no card)
   - **Together.ai** — [api.together.ai](https://api.together.ai/settings/api-keys)
   - **OpenAI** — [platform.openai.com](https://platform.openai.com/api-keys)
   - **Anthropic** — [console.anthropic.com](https://console.anthropic.com)
   - **xAI** — [console.x.ai](https://console.x.ai)
4. Pick a model and a 3D library
5. Tap **Save** — settings persist to `UserDefaults` and are restored on relaunch

### First scene

Ask for something in the chat:

> Create a glowing green planet with rings and three orbiting moons

Then keep going — *"make the planet blue"*, *"add stars"*, *"speed up the
moons"* — each message edits the scene you already have rather than rebuilding
it.

---

## Architecture

```
┌──────────────────────────────────────────┐
│  SwiftUI                                  │
│  ContentView · EnhancedChatView ·        │
│  ExamplesView · FavoritesView ·          │
│  ConversationHistoryView · Settings      │
└───────────────┬──────────────────────────┘
                │ @Published / Combine
┌───────────────┴──────────────────────────┐
│  ChatViewModel                            │
│  + RAG and Database extensions            │
└──┬─────────────────┬─────────────────┬───┘
   │                 │                 │
┌──┴───────────┐ ┌───┴──────────┐ ┌───┴──────────┐
│ AIProvider   │ │ Library3D    │ │ GRDB/SQLite  │
│ Manager      │ │ Manager      │ │ + VectorSearch│
│ (5 providers)│ │ (6 libraries)│ │ + Embeddings  │
└──────────────┘ └───┬──────────┘ └───────────────┘
                     │
      ┌──────────────┴───────────────┐
      │ WKWebView playground          │
      │ Monaco + the selected engine  │
      │ Sandpack / CodeSandbox for    │
      │ the React frameworks          │
      │ Nova64 studio runner (iframe) │
      └───────────────────────────────┘
```

**Key types**

- **`ChatViewModel`** — AI integration hub; `@MainActor`, `@Published` state,
  extended for RAG and database access
- **`AIProviderManager`** — provider selection and routing across the five
  provider clients
- **`Library3DManager`** / **`Library3DFactory`** — 3D framework registry,
  prompt and template selection, persisted choice
- **`WebViewCoordinator`** — Swift ↔ JavaScript bridge into the playground
- **`DatabaseManager`**, **`VectorSearchService`**, **`EmbeddingService`**,
  **`RAGContextBuilder`** — local retrieval stack
- **`CodeSandboxService`** / **`SecureCodeSandboxService`** / **`SandpackWebView`** —
  build pipeline for React Three Fiber and Reactylon
- **`AdManager`** / **`AdBannerView`** — monetization

---

## Technology stack

**iOS** — Swift 5.9+, SwiftUI, Combine, WebKit, iOS 18.0 deployment target

**AI** — AIProxySwift (Together.ai), LlamaStackClient (Meta models), plus
first-party HTTP clients for OpenAI, Anthropic, Google AI and xAI

**Storage** — GRDB.swift (SQLite) for conversations, favorites and RAG;
`UserDefaults` for settings

**Web layer** — Monaco Editor, Babylon.js, Three.js, A-Frame, React Three
Fiber, Reactylon, Nova64; Sandpack for the frameworks that need bundling

**Monetization** — Google Mobile Ads, Unity Ads, Google User Messaging Platform

---

## Project structure

```
iOSMaigeXr/
├── XRAiAssistant/
│   ├── XRAiAssistant.swift              # app entry
│   ├── ContentView.swift                # root tab layout
│   ├── ChatViewModel.swift              # AI integration hub
│   ├── WebViewCoordinator.swift         # Swift ↔ JS bridge
│   ├── SplashScreenView.swift
│   ├── SplashWebView.swift
│   ├── AIProviders/
│   │   ├── AIProvider.swift             # protocol
│   │   ├── AIProviderManager.swift      # selection + routing
│   │   ├── TogetherAIProvider.swift
│   │   ├── OpenAIProvider.swift
│   │   ├── AnthropicProvider.swift
│   │   ├── GoogleAIProvider.swift
│   │   └── XAIProvider.swift
│   ├── Library3D/
│   │   ├── Library3D.swift              # protocol + Library3DFactory
│   │   ├── Library3DManager.swift
│   │   ├── BabylonJSLibrary.swift
│   │   ├── ThreeJSLibrary.swift
│   │   ├── AFrameLibrary.swift
│   │   ├── ReactThreeFiberLibrary.swift
│   │   ├── ReactylonLibrary.swift
│   │   └── Nova64Library.swift
│   ├── Database/                        # GRDB manager + migrations
│   ├── RAG/                             # embeddings, vector search, context
│   ├── Views/                           # chat, examples, favorites,
│   │                                    # history, threaded messages
│   ├── Models/                          # conversation + favorite models
│   ├── Monetization/                    # AdManager, AdBannerView
│   ├── Theme/                           # neon cyberpunk theme
│   ├── Config/AppConfig.swift
│   ├── Resources/                       # playgrounds, splash.html
│   ├── BuildKit/                        # build tooling for React frameworks
│   ├── NodeWorker/                      # bundled Node worker
│   ├── Vendor/                          # vendored web assets
│   ├── CodeSandbox*.swift               # CodeSandbox / Sandpack integration
│   └── SandpackWebView.swift
├── XRAiAssistantTests/
├── Podfile                              # ad SDKs
└── docs/                                # status notes, build fixes, styling
```

---

## Status

**Working**

- Five AI providers with streaming, retry and effort-based controls
- Six 3D libraries with per-library prompts, templates and playgrounds
- Monaco editor and live scene rendering through the WebKit bridge
- Conversation history, threaded replies, favorites, examples browser
- GRDB/SQLite persistence with on-device vector search and embeddings
- Settings persistence with validation indicators and save confirmation
- Splash screen matched to Android and desktop

**In progress**

- Styling parity pass with the Android client — see
  [docs/STYLING_PROGRESS.md](docs/STYLING_PROGRESS.md)
- Multi-modal input (image understanding for scene analysis)

**Known limitations**

- **React Three Fiber and Reactylon need network access** for their CodeSandbox
  build step; the injection-based libraries and Nova64 do not.
- Several files under `docs/` are historical session notes and describe older
  model catalogs — [CLAUDE.md](CLAUDE.md) and this README are the current
  references.

---

## Documentation

- [CLAUDE.md](CLAUDE.md) — architecture and development guide
- [docs/STYLING_PROGRESS.md](docs/STYLING_PROGRESS.md) — theming progress
- [docs/COMMIT_MESSAGES.md](docs/COMMIT_MESSAGES.md) — session change log
- `WebMaigeXr/docs/NOVA64_INTEGRATION.md` — cross-platform Nova64 design notes
- `WebMaigeXr/docs/CHAT_MARKDOWN_RENDERING.md` — how a markdown line becomes a
  chat bubble, why inline-formatted paragraphs used to wrap into a narrow
  column, and how to run the renderer tests and snapshots

---

## License

MIT. Note that no `LICENSE` file is currently committed in this repository —
only `mcp-webgpu/` has one. Worth adding.

## Acknowledgments

- [Together.ai](https://together.ai) for accessible model APIs and a usable free tier
- The [Babylon.js](https://www.babylonjs.com/), [Three.js](https://threejs.org/),
  [A-Frame](https://aframe.io/) and [Nova64](https://nova64.io) projects
- [GRDB.swift](https://github.com/groue/GRDB.swift) and
  [AIProxySwift](https://github.com/lzell/AIProxySwift)
- The [WebXR community](https://www.w3.org/community/webxr/) for pushing the
  standards forward
