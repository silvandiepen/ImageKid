import CoreImage
import SwiftUI
import UIKit

/// An in-flight, non-destructive background mask: the working image it was
/// made from, the editable grayscale mask (white = kept subject), and the
/// composited live preview (subject at full strength, background dimmed so the
/// canvas backdrop shows what will be removed). Nothing is baked until Apply.
struct MaskSession {
    let base: UIImage
    let baseCG: CGImage
    var mask: CGImage
    var preview: UIImage
}

/// Identity captured when "Mask from Subject" starts its async cutout: the
/// picture and the exact history step the working image came from. The result
/// is installed only if the token still matches on completion — otherwise the
/// mask was built from pixels the user has since replaced (crop, undo, another
/// edit) and must be dropped rather than baked over the newer state.
struct MaskRequestToken: Equatable {
    let itemID: UUID?
    let historyStepID: UUID?
}

/// Mask compositing and painting. The removal engines return a composed
/// transparent cutout rather than a mask, so the mask is derived from the
/// cutout's alpha channel (v1) and edited as an opaque grayscale image that
/// CIBlendWithMask reads by luminance.
enum MaskRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Background dim level for the live preview — enough to see what the
    /// mask hides while the checkerboard reads through.
    private static let previewBackgroundAlpha: CGFloat = 0.25

    /// Extracts the cutout's alpha channel as an opaque grayscale mask
    /// (white = subject kept).
    static func alphaMask(of cutout: CGImage) -> CGImage? {
        let alphaToGray = CIImage(cgImage: cutout).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
        return context.createCGImage(alphaToGray, from: alphaToGray.extent)
    }

    /// Live preview: subject at full strength over the background dimmed to
    /// 25% opacity.
    static func preview(base: CGImage, mask: CGImage) -> CGImage? {
        blend(base: base, mask: mask, backgroundAlpha: previewBackgroundAlpha)
    }

    /// Bakes the mask: subject kept, background fully transparent.
    static func apply(base: CGImage, mask: CGImage) -> CGImage? {
        blend(base: base, mask: mask, backgroundAlpha: 0)
    }

    private static func blend(base: CGImage, mask: CGImage, backgroundAlpha: CGFloat) -> CGImage? {
        let baseCI = CIImage(cgImage: base)
        var maskCI = CIImage(cgImage: mask)
        if maskCI.extent.size != baseCI.extent.size, maskCI.extent.width > 0, maskCI.extent.height > 0 {
            maskCI = maskCI.transformed(by: CGAffineTransform(
                scaleX: baseCI.extent.width / maskCI.extent.width,
                y: baseCI.extent.height / maskCI.extent.height
            ))
        }

        let backdrop: CIImage
        if backgroundAlpha > 0 {
            // Scale every (premultiplied) component so the background dims
            // uniformly instead of going over-bright.
            backdrop = baseCI.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: backgroundAlpha, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: backgroundAlpha, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: backgroundAlpha, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: backgroundAlpha)
            ])
        } else {
            backdrop = CIImage(color: .clear).cropped(to: baseCI.extent)
        }

        guard let blend = CIFilter(name: "CIBlendWithMask") else { return nil }
        blend.setValue(baseCI, forKey: kCIInputImageKey)
        blend.setValue(backdrop, forKey: kCIInputBackgroundImageKey)
        blend.setValue(maskCI, forKey: "inputMaskImage")
        guard let output = blend.outputImage else { return nil }
        return context.createCGImage(output, from: baseCI.extent)
    }

    /// Paints one brush stroke into the mask: white reveals the image, black
    /// hides it to the background. Softness feathers the stroke edge with the
    /// same gaussian falloff the soft brushes use.
    static func paint(
        points: [CGPoint],
        reveal: Bool,
        widthFraction: CGFloat,
        softness: CGFloat,
        into mask: CGImage
    ) -> CGImage? {
        guard !points.isEmpty else { return mask }
        let size = CGSize(width: mask.width, height: mask.height)
        let full = CGRect(origin: .zero, size: size)
        let lineWidth = max(1, widthFraction * min(size.width, size.height))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        // The stroke alone at full alpha, then feathered, so soft edges blend
        // into the existing mask values.
        let strokeImage = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setStrokeColor(reveal ? UIColor.white.cgColor : UIColor.black.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setLineWidth(lineWidth)
            cg.addPath(RefineRenderer.strokePath(points, in: full))
            cg.strokePath()
        }
        guard let strokeCG = strokeImage.cgImage,
              let feathered = StrokeSoftener.blurred(strokeCG, radius: softness * lineWidth * 0.6) else {
            return nil
        }

        let output = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: mask).draw(in: full)
            UIImage(cgImage: feathered).draw(in: full)
        }
        return output.cgImage
    }
}

/// The Mask tool's options, host-agnostic: the iPad dock panel and the
/// compact inline inspector both wrap this. Before a mask exists it offers
/// "Mask from Subject"; afterwards it holds the Reveal/Hide brush toggle and
/// the shared size/softness sliders.
struct MaskControls: View {
    let hasMask: Bool
    let isBusy: Bool
    let engineTitle: String
    @Binding var revealMode: Bool
    @Binding var widthFraction: CGFloat
    @Binding var softness: CGFloat
    let onMaskFromSubject: () -> Void
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if !hasMask {
                Button(action: onMaskFromSubject) {
                    Label("Mask from Subject", systemImage: "person.and.background.dotted")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                Text("Finds the subject with \(engineTitle) and turns the background into an editable mask. Nothing is baked until you apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Brush", selection: $revealMode) {
                    Label("Reveal", systemImage: "eye").tag(true)
                    Label("Hide", systemImage: "eye.slash").tag(false)
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Brush size").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $widthFraction, in: 0.01...0.15)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Softness").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $softness, in: 0...1)
                }

                Text("Paint on the picture: Reveal brings hidden parts back, Hide removes more background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                Button(action: onApply) {
                    Label("Apply Mask", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasMask)
            }
        }
    }
}
