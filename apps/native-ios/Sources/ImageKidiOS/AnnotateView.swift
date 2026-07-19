import AVFoundation
import SwiftUI

/// Annotation editor: pick a tool, colour, and thickness, then drag on the image
/// to add shapes or freehand strokes. On apply, the annotations are flattened
/// onto the image at full resolution and returned via `onApply`.
struct AnnotateView: View {
    let image: UIImage
    let onApply: (CGImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var annotations: [Annotation] = []
    @State private var draft: Annotation?
    @State private var kind: Annotation.Kind = .rectangle
    @State private var color: Color = .red
    @State private var widthFraction: CGFloat = 0.008

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                canvas
                controls
            }
            .padding()
            .navigationTitle("Annotate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") { apply() }.bold().disabled(annotations.isEmpty)
                }
            }
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            let imageRect = AVMakeRect(
                aspectRatio: image.size,
                insideRect: CGRect(origin: .zero, size: geo.size)
            )
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                Canvas { context, _ in
                    for annotation in annotations + [draft].compactMap({ $0 }) {
                        context.stroke(
                            Path(annotation.path(in: imageRect)),
                            with: .color(annotation.color),
                            style: StrokeStyle(
                                lineWidth: annotation.strokeWidth(in: imageRect),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(drawGesture(in: imageRect))
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func drawGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = normalized(value.location, in: imageRect)
                if draft == nil {
                    var new = Annotation(kind: kind, color: color, widthFraction: widthFraction)
                    new.start = point
                    new.end = point
                    new.points = [point]
                    draft = new
                } else {
                    draft?.end = point
                    if kind == .freehand { draft?.points.append(point) }
                }
            }
            .onEnded { _ in
                if let draft { annotations.append(draft) }
                draft = nil
            }
    }

    private func normalized(_ point: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max((point.x - imageRect.minX) / imageRect.width, 0), 1),
            y: min(max((point.y - imageRect.minY) / imageRect.height, 0), 1)
        )
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Tool", selection: $kind) {
                ForEach(Annotation.Kind.allCases) { kind in
                    Image(systemName: kind.systemImage).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 16) {
                ColorPicker("Colour", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thickness").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $widthFraction, in: 0.002...0.02)
                }
                Button {
                    if !annotations.isEmpty { annotations.removeLast() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(annotations.isEmpty)
                Button(role: .destructive) {
                    annotations.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(annotations.isEmpty)
            }
        }
    }

    private func apply() {
        guard let base = image.normalizedCGImage(),
              let rendered = AnnotationRasterizer.render(annotations, onto: base) else {
            dismiss()
            return
        }
        onApply(rendered)
        dismiss()
    }
}
