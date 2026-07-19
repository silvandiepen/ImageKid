import SwiftUI

/// Prompted-edit sheet. The OpenAI key is stored in the Keychain; the image and
/// prompt are sent to OpenAI only when the user taps Generate.
struct PromptEditView: View {
    let onRun: (_ prompt: String, _ apiKey: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var prompt = ""

    private let account = "openai-api-key"

    private var canRun: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI API key") {
                    SecureField("sk-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Stored in your device Keychain. Tapping Generate sends the current image and your prompt to OpenAI.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Prompt") {
                    TextField("Describe the edit", text: $prompt, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Button {
                        KeychainStore.set(apiKey, for: account)
                        onRun(prompt, apiKey)
                        dismiss()
                    } label: {
                        Label("Generate", systemImage: "wand.and.stars")
                    }
                    .disabled(!canRun)
                }
            }
            .navigationTitle("Prompt edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .onAppear {
                if apiKey.isEmpty { apiKey = KeychainStore.string(for: account) ?? "" }
            }
        }
    }
}
