import AVFoundation
import SwiftUI

/// Annotation editor: pick a tool, colour, and thickness, then drag on the image
/// to add shapes or freehand strokes. On apply, the annotations are flattened
/// onto the image at full resolution and returned via `onApply`.
struct AnnotateView: View {
    let image: UIImage
    let onApply: (CGImage) -> Void

    init(image: UIImage, initialKind: Annotation.Kind = .rectangle, onApply: @escaping (CGImage) -> Void) {
        self.image = image
        self.onApply = onApply
        _kind = State(initialValue: initialKind)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var annotations: [Annotation] = []
    @State private var draft: Annotation?
    @State private var kind: Annotation.Kind
    @State private var color: Color = .red
    @State private var widthFraction: CGFloat = 0.008
    @State private var textSizeFraction: CGFloat = 0.05
    @State private var isEnteringText = false
    @State private var textInput = ""
    @State private var pendingTextLocation: CGPoint?

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
            .alert("Add text", isPresented: $isEnteringText) {
                TextField("Text", text: $textInput)
                Button("Add") { addText() }
                Button("Cancel", role: .cancel) { pendingTextLocation = nil }
            } message: {
                Text("Enter the text to place on the image.")
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
                        if annotation.isText {
                            let resolved = context.resolve(
                                Text(annotation.text.isEmpty ? " " : annotation.text)
                                    .font(.system(size: annotation.fontSize(in: imageRect)))
                                    .foregroundColor(annotation.color)
                            )
                            context.draw(resolved, at: annotation.textOrigin(in: imageRect), anchor: .topLeading)
                            continue
                        }
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
                guard kind != .text else { return }
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
            .onEnded { value in
                if kind == .text {
                    pendingTextLocation = normalized(value.location, in: imageRect)
                    textInput = ""
                    isEnteringText = true
                    return
                }
                if let draft { annotations.append(draft) }
                draft = nil
            }
    }

    private func addText() {
        let trimmed = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let location = pendingTextLocation else { return }
        var annotation = Annotation(kind: .text, color: color, widthFraction: widthFraction)
        annotation.start = location
        annotation.text = trimmed
        annotation.fontFraction = textSizeFraction
        annotations.append(annotation)
        pendingTextLocation = nil
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
                    if kind == .text {
                        Text("Text size").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $textSizeFraction, in: 0.02...0.15)
                    } else {
                        Text("Thickness").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $widthFraction, in: 0.002...0.02)
                    }
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
