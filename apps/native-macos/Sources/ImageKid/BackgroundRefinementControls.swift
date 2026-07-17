import SwiftUI

struct BackgroundRefinementControls: View {
    @ObservedObject var session: ImageSession
    @Binding var offset: CGSize
    let onUndo: () -> Void
    let onClose: () -> Void

    var body: some View {
        FloatingToolPanel(
            title: "Refine Background",
            systemImage: "paintbrush.pointed",
            width: 300,
            offset: $offset,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 18) {
                field("Brush") {
                    Picker("Brush", selection: $session.backgroundRefinementMode) {
                        ForEach(BackgroundRefinementMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                field("Size") {
                    HStack(spacing: 10) {
                        Slider(value: $session.backgroundBrushSize, in: 4...160, step: 1)
                        Text("\(Int(session.backgroundBrushSize))")
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .frame(width: 38, alignment: .trailing)
                    }
                }

                field("Softness") {
                    HStack(spacing: 10) {
                        Slider(value: $session.backgroundBrushSoftness, in: 0...0.9, step: 0.05)
                        Text("\(Int(session.backgroundBrushSoftness * 100))%")
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                field("Strength") {
                    HStack(spacing: 10) {
                        Slider(value: $session.backgroundBrushStrength, in: 0.1...1, step: 0.05)
                        Text("\(Int(session.backgroundBrushStrength * 100))%")
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                HStack(spacing: 10) {
                    Button("Undo Stroke", action: onUndo)
                        .disabled(session.backgroundRefinementUndoImage == nil)
                    Button("Done", action: onClose)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                Text("Remove paints pixels transparent. Keep restores pixels from the original image.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .darkPanelControl()
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
            content()
        }
    }
}
