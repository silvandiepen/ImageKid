import AppKit
import SwiftUI

struct ImageWorkspaceView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var session: ImageSession

    @State private var hoverControls = false
    @State private var interactionStart: CGPoint?
    @State private var panAtStart: CGSize = .zero
    @State private var draftAnnotationRect: CGRect?
    @State private var magnificationStart: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let fitted = GeometryMapper.aspectFitRect(contentSize: session.pixelSize, in: bounds.insetBy(dx: 32, dy: 32))
            let imageRect = transformedRect(fitted)

            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                checkerboard(in: imageRect)

                Image(nsImage: session.sourceImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                annotations(in: imageRect)

                if let draftAnnotationRect {
                    Rectangle()
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: draftAnnotationRect.width, height: draftAnnotationRect.height)
                        .position(x: draftAnnotationRect.midX, y: draftAnnotationRect.midY)
                }

                if appModel.activeTool == .crop {
                    CropOverlay(imageRect: imageRect, normalizedRect: session.draftCropRect ?? session.cropRect)
                }

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(interactionGesture(in: imageRect))
                    .simultaneousGesture(zoomGesture)

                controls
            }
            .clipped()
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.15)) {
                    hoverControls = inside
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Spacer()

            if appModel.activeTool == .pickColor {
                ColorStrip(colors: session.sampledColors)
            }

            if appModel.activeTool == .crop {
                HStack {
                    Button("Cancel") {
                        session.draftCropRect = nil
                        appModel.activeTool = .view
                    }
                    Button("Apply Crop") {
                        session.applyDraftCrop()
                        appModel.activeTool = .view
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(8)
                .background(.regularMaterial, in: Capsule())
            }

            FloatingToolbar(canExport: true)
                .opacity(hoverControls || appModel.activeTool != .view ? 1 : 0)
                .offset(y: hoverControls || appModel.activeTool != .view ? 0 : 8)
        }
        .padding(.bottom, 20)
        .animation(.easeOut(duration: 0.15), value: hoverControls)
    }

    @ViewBuilder
    private func checkerboard(in imageRect: CGRect) -> some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: imageRect.width, height: imageRect.height)
            .position(x: imageRect.midX, y: imageRect.midY)
            .overlay {
                Canvas { context, size in
                    let cell: CGFloat = 12
                    for row in 0...Int(size.height / cell) {
                        for column in 0...Int(size.width / cell) where (row + column).isMultiple(of: 2) {
                            context.fill(
                                Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                with: .color(.gray.opacity(0.18))
                            )
                        }
                    }
                }
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)
            }
    }

    @ViewBuilder
    private func annotations(in imageRect: CGRect) -> some View {
        ForEach(session.annotations) { annotation in
            let rect = GeometryMapper.viewRect(from: annotation.frame, in: imageRect)
            switch annotation.kind {
            case .rectangle:
                Rectangle()
                    .stroke(Color(nsColor: annotation.strokeColor), lineWidth: annotation.lineWidth)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            case .text(let value):
                Text(value)
                    .font(.system(size: max(13, rect.height * 0.35), weight: .semibold))
                    .foregroundStyle(Color(nsColor: annotation.strokeColor))
                    .frame(width: rect.width, height: rect.height, alignment: .leading)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func transformedRect(_ fitted: CGRect) -> CGRect {
        let width = fitted.width * session.zoom
        let height = fitted.height * session.zoom
        return CGRect(
            x: fitted.midX - width / 2 + session.pan.width,
            y: fitted.midY - height / 2 + session.pan.height,
            width: width,
            height: height
        )
    }

    private func interactionGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if interactionStart == nil {
                    interactionStart = value.startLocation
                    panAtStart = session.pan
                }

                switch appModel.activeTool {
                case .view:
                    session.pan = CGSize(
                        width: panAtStart.width + value.translation.width,
                        height: panAtStart.height + value.translation.height
                    )

                case .crop:
                    session.draftCropRect = GeometryMapper.normalizedRect(
                        from: value.startLocation,
                        to: value.location,
                        in: imageRect
                    )

                case .rectangle:
                    draftAnnotationRect = rect(from: value.startLocation, to: value.location)

                case .pickColor, .text:
                    break
                }
            }
            .onEnded { value in
                defer {
                    interactionStart = nil
                    draftAnnotationRect = nil
                }

                guard let normalized = GeometryMapper.normalizedPoint(value.location, in: imageRect) else { return }

                switch appModel.activeTool {
                case .pickColor:
                    if let color = PixelSampler.color(in: session.sourceImage, at: normalized) {
                        session.addSample(color)
                    }

                case .rectangle:
                    guard let normalizedRect = GeometryMapper.normalizedRect(
                        from: value.startLocation,
                        to: value.location,
                        in: imageRect
                    ), normalizedRect.width > 0.005, normalizedRect.height > 0.005 else { return }
                    session.annotations.append(Annotation(kind: .rectangle, frame: normalizedRect))
                    session.isDirty = true

                case .text:
                    let frame = CGRect(
                        x: min(normalized.x, 0.72),
                        y: min(normalized.y, 0.9),
                        width: 0.25,
                        height: 0.08
                    )
                    session.annotations.append(Annotation(kind: .text("Text"), frame: frame))
                    session.isDirty = true

                case .view, .crop:
                    break
                }
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                session.zoom = min(max(magnificationStart * value, 0.1), 12)
            }
            .onEnded { _ in
                magnificationStart = session.zoom
            }
    }

    private func rect(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }
}
