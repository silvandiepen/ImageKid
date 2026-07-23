import SwiftUI
import ImageKidCore
import ImageKidKit

/// Floating panel for customising the canvas grid: visibility, snapping,
/// spacing, subdivisions, colour and opacity.
struct GridControls: View {
    @ObservedObject var session: ImageSession
    @Binding var offset: CGSize
    let onClose: () -> Void

    private let sizePresets: [Int] = [8, 16, 32, 64, 128, 256]

    var body: some View {
        FloatingToolPanel(
            title: "Grid",
            systemImage: "grid",
            width: 300,
            offset: $offset,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Show grid", isOn: $session.showGrid)
                Toggle("Snap to grid", isOn: $session.snapToGrid)

                Rectangle().fill(.white.opacity(0.09)).frame(height: 1)

                field("Size") {
                    HStack(spacing: 10) {
                        MinimalSlider(value: $session.gridSizePx, in: 4...512, step: 1)
                        Text("\(Int(session.gridSizePx)) px")
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .frame(width: 56, alignment: .trailing)
                    }
                    HStack(spacing: 5) {
                        ForEach(sizePresets, id: \.self) { size in
                            Button("\(size)") { session.gridSizePx = CGFloat(size) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(Int(session.gridSizePx) == size ? .accentColor : nil)
                        }
                    }
                }

                field("Subdivisions") {
                    HStack(spacing: 10) {
                        MinimalSlider(
                            value: Binding(
                                get: { Double(session.gridSubdivisions) },
                                set: { session.gridSubdivisions = Int($0.rounded()) }
                            ),
                            in: 1...8, step: 1
                        )
                        Text("\(session.gridSubdivisions)×")
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                field("Colour") {
                    HStack(spacing: 10) {
                        ColorPicker("", selection: gridColorBinding, supportsOpacity: false)
                            .labelsHidden()
                        MinimalSlider(value: $session.gridOpacity, in: 0.03...1, step: 0.01)
                        Text("\(Int(session.gridOpacity * 100))%")
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
            .darkPanelControl()
        }
    }

    private var gridColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: session.gridColor) },
            set: { session.gridColorHex = ColorHex.string(from: NSColor($0)) }
        )
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
