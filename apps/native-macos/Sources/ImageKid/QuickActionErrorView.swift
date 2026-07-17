import AppKit
import SwiftUI

struct QuickActionErrorView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("ImageKid quick action failed", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Close") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}
