import SwiftUI
import ImageKidCore
import ImageKidKit

/// Fast transforms for the selected image layer: rotate, flip, scale, reset.
struct TransformControls: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var session: ImageSession
    let layerID: UUID
    @Binding var offset: CGSize
    var dockEdges: (leadingFlat: Bool, trailingFlat: Bool) = (false, false)
    let onClose: () -> Void

    private var layer: ImageLayer? { session.imageLayers.first(where: { $0.id == layerID }) }

    var body: some View {
        FloatingToolPanel(
            title: "Transform",
            systemImage: "crop.rotate",
            width: 280,
            offset: $offset,
            onClose: onClose,
            dockEdges: dockEdges
        ) {
            VStack(alignment: .leading, spacing: 16) {
                field("Rotate") {
                    HStack(spacing: 8) {
                        iconButton("rotate.left", "Rotate 90° left") { session.rotateLayer90(id: layerID, clockwise: false) }
                        iconButton("rotate.right", "Rotate 90° right") { session.rotateLayer90(id: layerID, clockwise: true) }
                        Spacer()
                        TextField("", value: rotationBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)
                        Text("°").foregroundStyle(Color.panelInk(colorScheme, 0.55))
                    }
                    MinimalSlider(value: rotationBinding, in: -180...180, step: 1)
                }

                field("Flip") {
                    HStack(spacing: 8) {
                        toggleButton("arrow.left.and.right", "Flip horizontal", on: layer?.flipH ?? false) {
                            session.flipLayer(id: layerID, horizontal: true)
                        }
                        toggleButton("arrow.up.and.down", "Flip vertical", on: layer?.flipV ?? false) {
                            session.flipLayer(id: layerID, horizontal: false)
                        }
                        Spacer()
                    }
                }

                field("Size") {
                    HStack(spacing: 7) {
                        Button("50%") { session.scaleLayer(id: layerID, factor: 0.5) }
                        Button("2×") { session.scaleLayer(id: layerID, factor: 2) }
                        Button("Fit") { session.fitLayerToCanvas(id: layerID) }
                    }
                    .buttonStyle(.bordered)
                }

                Rectangle().fill(Color.panelFill(colorScheme, 0.09)).frame(height: 1)

                HStack {
                    Button("Reset") { session.resetLayerTransform(id: layerID) }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Done") { onClose() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .darkPanelControl()
        }
    }

    private var rotationBinding: Binding<Double> {
        Binding(
            get: { layer?.rotation ?? 0 },
            set: { session.setLayerRotation(id: layerID, degrees: $0) }
        )
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 30)
                .background(Color.panelFill(colorScheme, 0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func toggleButton(_ symbol: String, _ help: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 30)
                .background(on ? Color.accentColor.opacity(0.5) : Color.panelFill(colorScheme, 0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.panelInk(colorScheme, 0.72))
            content()
        }
    }
}
