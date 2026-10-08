import SwiftUI

/// Asks for a provider's API key right where it is needed: sending a message,
/// picking a model, or after a key error. Matches the Android prompt.
struct APIKeyEntrySheet: View {
    let provider: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var key = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section {
                    SecureField("Paste your \(provider) key", text: $key)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityLabel("\(provider) API key")
                } header: {
                    Text("\(provider) API key")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This model needs your own \(provider) key. It stays on this device, in the Keychain, and is sent only to \(provider).")
                        if let url = URL(string: Self.keyPage(for: provider)) {
                            Link("Get your \(provider) key", destination: url)
                        }
                    }
                }
            }
            .navigationTitle("Add your key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedKey.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmedKey.isEmpty else { return }
        onSave(trimmedKey)
    }

    /// Where to get a key for each provider.
    static func keyPage(for provider: String) -> String {
        switch provider {
        case "OpenAI": return "https://platform.openai.com/api-keys"
        case "Anthropic": return "https://console.anthropic.com/settings/keys"
        case "Google AI": return "https://aistudio.google.com/apikey"
        case "xAI": return "https://console.x.ai"
        default: return "https://api.together.ai/settings/api-keys"
        }
    }
}

/// A provider name usable with `.sheet(item:)`.
struct KeyPrompt: Identifiable, Equatable {
    let provider: String
    var id: String { provider }
}
