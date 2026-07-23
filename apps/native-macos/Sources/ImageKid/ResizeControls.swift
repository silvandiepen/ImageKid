import SwiftUI
import ImageKidKit

struct ResizeControls: View {
    @ObservedObject var session: ImageSession
    @Binding var offset: CGSize
    var dockEdges: (leadingFlat: Bool, trailingFlat: Bool) = (false, false)
    let isApplying: Bool
    let onCancel: () -> Void
    let onApply: () -> Void
    let onSmartUpscale: (EnhanceSize) -> Void

    @State private var customPercent = 100

    var body: some View {
        FloatingToolPanel(
            title: "Image Size",
            systemImage: "arrow.up.left.and.arrow.down.right",
            width: 310,
            offset: $offset,
            onClose: onCancel,
            dockEdges: dockEdges
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Resamples the whole document — canvas and every layer scale together.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)

                    field("New size") {
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

                    Toggle("Preserve aspect ratio", isOn: $session.resizePreservesAspect)

                    field("Scale") {
                        HStack(spacing: 7) {
                            Button("50%") { setPercent(50) }
                            Button("100%") { setPercent(100) }
                            Button("200%") { setPercent(200) }
                            Button("400%") { setPercent(400) }
                        }
                        .buttonStyle(.bordered)

                        HStack(spacing: 8) {
                            MinimalSlider(value: customPercentBinding, in: 10...800, step: 1)
                            TextField("Percent", value: customPercentBinding, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("%")
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }

                    Button {
                        session.setDraftOutputSize(session.croppedPixelSize)
                    } label: {
                        Label("Reset Size", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(isApplying ? "Applying…" : "Apply Resize", action: onApply)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(isApplying)

                    Divider().overlay(.white.opacity(0.12))

                    field("Smart Upscale") {
                        HStack(spacing: 7) {
                            Button("Enhance") { onSmartUpscale(.same) }
                            Button("2×") { onSmartUpscale(.x2) }
                            Button("4×") { onSmartUpscale(.x4) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isApplying)

                        Text("Enlarge with more detail on-device.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                if isApplying {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                }
            }
            .darkPanelControl()
        }
        .disabled(isApplying)
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

    private var currentSize: CGSize {
        session.draftOutputSize ?? session.resizePreviewSize
    }

    private var widthBinding: Binding<Int> {
        Binding(
            get: { max(1, Int(currentSize.width.rounded())) },
            set: { setWidth($0) }
        )
    }

    private var heightBinding: Binding<Int> {
        Binding(
            get: { max(1, Int(currentSize.height.rounded())) },
            set: { setHeight($0) }
        )
    }

    private var customPercentBinding: Binding<Double> {
        Binding(
            get: { Double(customPercent) },
            set: { setPercent(Int($0.rounded())) }
        )
    }

    private func setWidth(_ pixels: Int) {
        let width = max(1, CGFloat(pixels))
        if session.resizePreservesAspect {
            let ratio = session.croppedPixelSize.height / max(session.croppedPixelSize.width, 1)
            session.setDraftOutputSize(CGSize(width: width, height: width * ratio))
        } else {
            session.setDraftOutputSize(CGSize(width: width, height: currentSize.height))
        }
    }

    private func setHeight(_ pixels: Int) {
        let height = max(1, CGFloat(pixels))
        if session.resizePreservesAspect {
            let ratio = session.croppedPixelSize.width / max(session.croppedPixelSize.height, 1)
            session.setDraftOutputSize(CGSize(width: height * ratio, height: height))
        } else {
            session.setDraftOutputSize(CGSize(width: currentSize.width, height: height))
        }
    }

    private func setScale(_ scale: CGFloat) {
        session.setDraftOutputSize(CGSize(
            width: session.croppedPixelSize.width * scale,
            height: session.croppedPixelSize.height * scale
        ))
    }

    private func setPercent(_ percent: Int) {
        let clampedPercent = min(max(percent, 10), 800)
        customPercent = clampedPercent
        setScale(CGFloat(clampedPercent) / 100)
    }
}
