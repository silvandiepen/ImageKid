import SwiftUI

struct PromptEditSheet: View {
    let isApplying: Bool
    let providerName: String
    let hasCredential: Bool
    let sendsSelectionOnly: Bool
    let onCancel: () -> Void
    let onApply: (String) -> Void

    @State private var prompt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Magic", systemImage: "sparkles")
                    .font(.title3.weight(.semibold))

                Text(disclosureText)
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

            Text("Core ImageKid tools remain local. Magic sends \(payloadName) and your prompt to \(providerName) using your saved provider key.")
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

    private var disclosureText: String {
        if sendsSelectionOnly {
            return "Describe how to change the selected area. ImageKid will send only that selected crop and your prompt to the configured provider, then place the result back into this image."
        }
        return "Describe how to change the whole rendered image. ImageKid will send that image and your prompt to the configured provider, then replace this workspace image with the result."
    }

    private var payloadName: String {
        sendsSelectionOnly ? "the selected crop" : "the rendered image"
    }
}
