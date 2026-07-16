import SwiftUI

struct CropControls: View {
    @ObservedObject var session: ImageSession
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker("Ratio", selection: $session.cropAspectRatio) {
                ForEach(CropAspectRatio.allCases) { ratio in
                    Text(ratio.label).tag(ratio)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 112)
            .onChange(of: session.cropAspectRatio) { _, value in
                applyRatio(value)
            }

            Divider().frame(height: 24)

            HStack(spacing: 6) {
                TextField("Width", value: widthBinding, format: .number)
                    .frame(width: 74)
                    .textFieldStyle(.roundedBorder)
                Text("×")
                    .foregroundStyle(.secondary)
                TextField("Height", value: heightBinding, format: .number)
                    .frame(width: 74)
                    .textFieldStyle(.roundedBorder)
                Text("px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 24)

            Button("Reset") {
                session.draftCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                session.cropAspectRatio = .free
            }

            Button("Cancel", action: onCancel)

            Button("Apply", action: onApply)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.regular)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        )
        .shadow(color: .black.opacity(0.2), radius: 18, y: 7)
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
