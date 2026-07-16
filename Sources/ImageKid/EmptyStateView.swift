import SwiftUI

struct EmptyStateView: View {
    let isDropTarget: Bool
    let openAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Drop an image or video")
                    .font(.title3.weight(.semibold))
                Text("or open a local file")
                    .foregroundStyle(.secondary)
            }

            Button("Open…", action: openAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTarget ? Color.accentColor.opacity(0.08) : .clear)
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    isDropTarget ? Color.accentColor : Color.secondary.opacity(0.18),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 8])
                )
                .padding(32)
        }
    }
}
