import SwiftUI
import ImageKidCore
import ImageKidKit

struct CropControls: View {
    @ObservedObject var session: ImageSession
    @Binding var offset: CGSize
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        FloatingToolPanel(
            title: "Crop",
            systemImage: "crop",
            width: 290,
            offset: $offset,
            onClose: onCancel
        ) {
            VStack(alignment: .leading, spacing: 18) {
                field("Ratio") {
                    Picker("Ratio", selection: $session.cropAspectRatio) {
                        ForEach(CropAspectRatio.allCases) { ratio in
                            Text(ratio.label).tag(ratio)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .onChange(of: session.cropAspectRatio) { _, value in
                        applyRatio(value)
                    }
                }

                field("Size") {
                    HStack(spacing: 8) {
                        TextField("Width", value: widthBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                        Text("×")
                            .foregroundStyle(.white.opacity(0.55))
                        TextField("Height", value: heightBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("Pixels")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.48))
                }

                Toggle("Snap to grid", isOn: $session.snapToGrid)
                    .font(.caption.weight(.medium))

                Toggle("Delete content outside crop", isOn: $session.cropTrimsOutsideContent)
                    .font(.caption.weight(.medium))

                Text("Drag corners or edges to resize. Drag inside the crop to move it.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle()
                    .fill(.white.opacity(0.09))
                    .frame(height: 1)

                Button {
                    session.draftCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                    session.cropAspectRatio = .free
                } label: {
                    Label("Reset Crop", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel)
                        .frame(maxWidth: .infinity)
                    Button("Apply", action: onApply)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
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

    private var currentRect: CGRect {
        session.draftCropRect ?? session.cropRect
    }

    private var widthBinding: Binding<Int> {
        Binding(
            get: { max(1, Int((currentRect.width * session.pixelSize.width).rounded())) },
            set: { setPixelWidth($0) }
        )
    }

    private var heightBinding: Binding<Int> {
        Binding(
            get: { max(1, Int((currentRect.height * session.pixelSize.height).rounded())) },
            set: { setPixelHeight($0) }
        )
    }

    private func setPixelWidth(_ pixels: Int) {
        var rect = currentRect
        rect.size.width = min(max(CGFloat(pixels) / session.pixelSize.width, 0.01), 1)
        if let ratio = session.cropAspectRatio.ratio(for: session.pixelSize) {
            let pixelHeight = CGFloat(pixels) / ratio
            rect.size.height = min(max(pixelHeight / session.pixelSize.height, 0.01), 1)
        }
        session.draftCropRect = GeometryMapper.clampedNormalizedRect(rect)
    }

    private func setPixelHeight(_ pixels: Int) {
        var rect = currentRect
        rect.size.height = min(max(CGFloat(pixels) / session.pixelSize.height, 0.01), 1)
        if let ratio = session.cropAspectRatio.ratio(for: session.pixelSize) {
            let pixelWidth = CGFloat(pixels) * ratio
            rect.size.width = min(max(pixelWidth / session.pixelSize.width, 0.01), 1)
        }
        session.draftCropRect = GeometryMapper.clampedNormalizedRect(rect)
    }

    private func applyRatio(_ aspect: CropAspectRatio) {
        guard let ratio = aspect.ratio(for: session.pixelSize) else { return }
        let rect = currentRect
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let pixelWidth = rect.width * session.pixelSize.width
        let pixelHeight = rect.height * session.pixelSize.height

        var newWidth = rect.width
        var newHeight = rect.height
        if pixelWidth / max(pixelHeight, 1) > ratio {
            newWidth = (pixelHeight * ratio) / session.pixelSize.width
        } else {
            newHeight = (pixelWidth / ratio) / session.pixelSize.height
        }

        session.draftCropRect = GeometryMapper.clampedNormalizedRect(
            CGRect(
                x: center.x - newWidth / 2,
                y: center.y - newHeight / 2,
                width: newWidth,
                height: newHeight
            )
        )
    }
}
