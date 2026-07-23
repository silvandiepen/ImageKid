import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// A single refinement brush stroke in normalised coordinates.
struct RefineStroke: Identifiable {
    let id = UUID()
    var keep: Bool
    var points: [CGPoint]
    var widthFraction: CGFloat
    /// Soft edge (0 = hard, 1 = very soft) and effect strength (0…1).
    var softness: CGFloat = 0
    var strength: CGFloat = 1
}

/// Manual cutout refinement: erase leftover background or restore parts that
/// removal took by mistake. Doubles as a plain eraser when no removal was done.
struct RefineView: View {
    let original: CGImage
    let current: CGImage
    let onApply: (CGImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [RefineStroke] = []
    @State private var draft: RefineStroke?
    @State private var keepMode = false
    @State private var widthFraction: CGFloat = 0.04
    @State private var softness: CGFloat = 0.3
    @State private var strength: CGFloat = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                canvas
                controls
            }
            .padding()
            .navigationTitle("Refine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") { apply() }.bold().disabled(strokes.isEmpty)
                }
            }
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            let imageRect = AVMakeRect(
                aspectRatio: CGSize(width: current.width, height: current.height),
                insideRect: CGRect(origin: .zero, size: geo.size)
            )
            ZStack {
                Image(uiImage: UIImage(cgImage: current))
                    .resizable()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                Canvas { context, _ in
                    for stroke in strokes + [draft].compactMap({ $0 }) {
                        context.stroke(
                            Path(RefineRenderer.strokePath(stroke.points, in: imageRect)),
                            with: .color((stroke.keep ? Color.green : Color.red).opacity(0.45)),
                            style: StrokeStyle(
                                lineWidth: max(1, stroke.widthFraction * min(imageRect.width, imageRect.height)),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(brushGesture(in: imageRect))
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func brushGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = CGPoint(
                    x: min(max((value.location.x - imageRect.minX) / imageRect.width, 0), 1),
                    y: min(max((value.location.y - imageRect.minY) / imageRect.height, 0), 1)
                )
                if draft == nil {
                    draft = RefineStroke(keep: keepMode, points: [point], widthFraction: widthFraction,
                                         softness: softness, strength: strength)
                } else {
                    draft?.points.append(point)
                }
            }
            .onEnded { _ in
                if let draft { strokes.append(draft) }
                draft = nil
            }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $keepMode) {
                Text("Erase").tag(false)
                Text("Restore").tag(true)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 16) {
                labeledSlider("Size", value: $widthFraction, in: 0.01...0.12)
                labeledSlider("Softness", value: $softness, in: 0...1)
                labeledSlider("Strength", value: $strength, in: 0.1...1)
            }

            HStack(spacing: 16) {
                Spacer()
                Button {
                    if !strokes.isEmpty { strokes.removeLast() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(strokes.isEmpty)
                Button(role: .destructive) {
                    strokes.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(strokes.isEmpty)
            }

            Text("Erase removes background; Restore paints the original back. Restore works best right after background removal.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func labeledSlider(_ title: String, value: Binding<CGFloat>, in range: ClosedRange<CGFloat>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Slider(value: value, in: range)
        }
    }

    private func apply() {
        guard let rendered = RefineRenderer.render(original: original, current: current, strokes: strokes) else {
            dismiss()
            return
        }
        onApply(rendered)
        dismiss()
    }
}

enum RefineRenderer {
    static func strokePath(_ points: [CGPoint], in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
        }
        path.move(to: map(first))
        if points.count == 1 {
            path.addLine(to: map(first)) // a dot with a round cap
        } else {
            for point in points.dropFirst() { path.addLine(to: map(point)) }
        }
        return path
    }

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// A brush-stroke coverage mask (transparent → opaque white along the stroke),
    /// softened by `softness`. Used both to clip a restore and to subtract alpha
    /// for an erase, so the edge feathers instead of being hard.
    private static func strokeMask(_ stroke: RefineStroke, size: CGSize) -> CGImage? {
        let width = max(1, stroke.widthFraction * min(size.width, size.height))
        let full = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(width)
            cg.addPath(strokePath(stroke.points, in: full))
            cg.strokePath()
        }
        guard let base = img.cgImage else { return nil }
        guard stroke.softness > 0.001 else { return base }
        let ci = CIImage(cgImage: base)
        let radius = stroke.softness * width / 2
        let blurred = ci.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: ci.extent)
        return ciContext.createCGImage(blurred, from: ci.extent) ?? base
    }

    /// Rebuilds the working image: starts from `current`, restores `original`
    /// pixels under "keep" strokes, and clears alpha under "erase" strokes —
    /// each stroke feathered by its softness and scaled by its strength.
    static func render(original: CGImage, current: CGImage, strokes: [RefineStroke]) -> CGImage? {
        let size = CGSize(width: current.width, height: current.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let full = CGRect(origin: .zero, size: size)

        let output = renderer.image { context in
            UIImage(cgImage: current).draw(in: full)
            let cg = context.cgContext

            for stroke in strokes {
                guard let mask = strokeMask(stroke, size: size) else { continue }
                let strength = max(0, min(stroke.strength, 1))
                if stroke.keep {
                    // Restore original pixels through the soft mask, at strength.
                    cg.saveGState()
                    cg.clip(to: full, mask: mask)
                    cg.setAlpha(strength)
                    UIImage(cgImage: original).draw(in: full)
                    cg.restoreGState()
                } else {
                    // Subtract alpha through the soft mask, at strength.
                    cg.saveGState()
                    cg.setBlendMode(.destinationOut)
                    cg.setAlpha(strength)
                    UIImage(cgImage: mask).draw(in: full)
                    cg.restoreGState()
                }
            }
        }
        return output.cgImage
    }
}
