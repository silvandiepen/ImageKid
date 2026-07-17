import SwiftUI

struct PromptEditSheet: View {
    let isApplying: Bool
    let providerName: String
    let hasCredential: Bool
    let onCancel: () -> Void
    let onApply: (String) -> Void

    @State private var prompt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Magic", systemImage: "sparkles")
                    .font(.title3.weight(.semibold))

                Text("Describe how to change the current image. ImageKid will send the rendered image and prompt to the configured provider, then replace this workspace image with the result.")
                    .foregroundStyle(.secondary)
            }

            if !hasCredential {
                Label(
                    "Add a \(providerName) key in Settings before using prompted edits.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.secondary.opacity(0.3))
                )
                .disabled(isApplying)

            Text("Core ImageKid tools remain local. The current provider is \(providerName), so this action uses your saved provider key and requires a network connection.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .disabled(isApplying)
                    .keyboardShortcut(.cancelAction)
                Button(isApplying ? "Editing…" : "Do Magic") {
                    onApply(prompt)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying || !hasCredential || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}
