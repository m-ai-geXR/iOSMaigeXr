//
//  ChatViewModelExtension.swift
//  XRAiAssistant
//
//  SQLite-compatible settings persistence for ChatViewModel
//  This file provides async versions of saveSettings and loadSettings
//

import Foundation

extension ChatViewModel {

    /// Save settings to SQLite database (async)
    func saveSettingsSQLite() async {
        print("💾 Saving settings to SQLite...")

        do {
            let db = DatabaseManager.shared

            // Save general settings
            try await db.saveSetting(key: "XRAiAssistant_APIKey", value: apiKey)
            try await db.saveSetting(key: "XRAiAssistant_SystemPrompt", value: systemPrompt)
            try await db.saveSetting(key: "XRAiAssistant_SelectedModel", value: selectedModel)
            try await db.saveSetting(key: "XRAiAssistant_Temperature", value: temperature)
            try await db.saveSetting(key: "XRAiAssistant_TopP", value: topP)

            // The AIProviderManager handles its own persistence automatically

            print("✅ Settings saved to SQLite successfully")
        } catch {
            print("❌ Failed to save settings to SQLite: \(error)")
        }
    }

    /// Load settings from SQLite database (async)
    func loadSettingsSQLite() async {
        print("📂 Loading settings from SQLite...")

        do {
            let db = DatabaseManager.shared

            // Load API key
            if let savedAPIKey = try await db.loadSetting(key: "XRAiAssistant_APIKey") as? String,
               savedAPIKey != DEFAULT_API_KEY {
                await MainActor.run {
                    apiKey = savedAPIKey
                    aiProviderManager.setAPIKey(for: "Together.ai", key: savedAPIKey)
                }
                print("🔑 Loaded saved API key: \(String(savedAPIKey.prefix(10)))...")
            } else {
                // Check provider system
                await MainActor.run {
                    let newProviderKey = aiProviderManager.getAPIKey(for: "Together.ai")
                    if newProviderKey != "changeMe" {
                        apiKey = newProviderKey
                        print("🔑 Using API key from provider system: \(String(newProviderKey.prefix(10)))...")
                    } else {
                        aiProviderManager.setAPIKey(for: "Together.ai", key: DEFAULT_API_KEY)
                        print("🔑 Using default API key")
                    }
                }
            }

            // Load system prompt
            if let savedSystemPrompt = try await db.loadSetting(key: "XRAiAssistant_SystemPrompt") as? String,
               !savedSystemPrompt.isEmpty {
                await MainActor.run {
                    systemPrompt = savedSystemPrompt
                }
                print("📝 Loaded custom system prompt (\(savedSystemPrompt.count) characters)")
            }

            // Load model selection
            if let savedModel = try await db.loadSetting(key: "XRAiAssistant_SelectedModel") as? String {
                print("📥 Found saved model in SQLite: \(savedModel)")

                let isProviderModel = aiProviderManager.getModel(id: savedModel) != nil

                // Model migration mappings
                let invalidModelMappings: [String: String] = [
                    "claude-sonnet-4.5-20250514": "claude-sonnet-4-5-20250929",
                    "claude-sonnet-4-5-20250514": "claude-sonnet-4-5-20250929",
                    "claude-opus-4.5-20250514": "claude-opus-4-1-20250805",
                    "Qwen/Qwen2.5-Coder-32B-Instruct": "deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free"
                ]

                await MainActor.run {
                    if let correctModel = invalidModelMappings[savedModel] {
                        print("⚠️ Migrating invalid model '\(savedModel)' to '\(correctModel)'")
                        selectedModel = correctModel
                        Task {
                            try? await db.saveSetting(key: "XRAiAssistant_SelectedModel", value: correctModel)
                        }
                        print("✅ Migration complete: \(getModelDisplayName(correctModel))")
                    } else if isProviderModel {
                        selectedModel = savedModel
                        print("🤖 Loaded saved model: \(getModelDisplayName(savedModel))")
                    } else {
                        // Model no longer exists
                        if savedModel.contains("claude") || savedModel.contains("anthropic") {
                            selectedModel = "claude-sonnet-4-5-20250929"
                            print("⚠️ Saved model '\(savedModel)' not found, switching to Claude Sonnet 4.5")
                        } else {
                            selectedModel = "deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free"
                            print("⚠️ Saved model '\(savedModel)' not available, using default")
                        }
                        Task {
                            try? await db.saveSetting(key: "XRAiAssistant_SelectedModel", value: selectedModel)
                        }
                    }
                }
            }

            // Load temperature
            if let temp = try await db.loadSetting(key: "XRAiAssistant_Temperature") as? Double {
                await MainActor.run {
                    temperature = temp
                }
                print("🌡️ Loaded temperature: \(temp)")
            }

            // Load top-p
            if let top = try await db.loadSetting(key: "XRAiAssistant_TopP") as? Double {
                await MainActor.run {
                    topP = top
                }
                print("📊 Loaded top-p: \(top)")
            }

            print("✅ Settings loaded from SQLite successfully")

        } catch {
            print("❌ Failed to load settings from SQLite: \(error)")
            // Fall back to UserDefaults if SQLite fails
            loadSettings()
        }
    }
}
