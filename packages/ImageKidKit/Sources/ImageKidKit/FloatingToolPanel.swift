import SwiftUI

/// A draggable, optionally minimizable and resizable floating panel with a dark
/// translucent chrome. App-agnostic: pass a title, icon, bindings, and content.
public struct FloatingToolPanel<Content: View>: View {
    let title: String
    let systemImage: String
    let width: CGFloat
    @Binding var offset: CGSize
    let onClose: (() -> Void)?
    let onMinimize: (() -> Void)?
    let snapStep: CGFloat?
    let resizable: Bool
    @Binding var size: CGSize
    let minSize: CGSize
    let maxSize: CGSize
    let cornerRadius: CGFloat
    let contentPadding: CGFloat
    let content: Content

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var resizeTranslation: CGSize = .zero
    @GestureState private var isDragging = false
    @State private var resizeHovering = false

    public init(
        title: String,
        systemImage: String,
        width: CGFloat = 300,
        offset: Binding<CGSize>,
        onClose: (() -> Void)? = nil,
        onMinimize: (() -> Void)? = nil,
        snapStep: CGFloat? = nil,
        resizable: Bool = false,
        size: Binding<CGSize> = .constant(.zero),
        minSize: CGSize = CGSize(width: 220, height: 200),
        maxSize: CGSize = CGSize(width: 520, height: 900),
        cornerRadius: CGFloat = 28,
        contentPadding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.width = width
        self._offset = offset
        self.onClose = onClose
        self.onMinimize = onMinimize
        self.snapStep = snapStep
        self.resizable = resizable
        self._size = size
        self.minSize = minSize
        self.maxSize = maxSize
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.content = content()
    }

    private var resolvedWidth: CGFloat {
        guard resizable else { return width }
        return max(minSize.width, size.width + resizeTranslation.width)
    }

    private var resolvedHeight: CGFloat? {
        guard resizable else { return nil }
        return max(minSize.height, size.height + resizeTranslation.height)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(.white.opacity(0.09))
                .frame(height: 1)

            content
                .padding(contentPadding)
                .frame(maxHeight: resizable ? .infinity : nil, alignment: .top)
        }
        .frame(width: resolvedWidth, height: resolvedHeight, alignment: .top)
        .foregroundStyle(.white)
        .background(
            Color.black.opacity(0.80),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .overlay(alignment: .bottomTrailing) {
            if resizable { resizeHandle }
        }
        // A large blurred shadow re-rasterises every frame while dragging, which
        // is the main source of drag stutter — shrink it hard during a drag.
        .shadow(color: .black.opacity(isDragging ? 0.28 : 0.36), radius: isDragging ? 6 : 28, y: isDragging ? 3 : 12)
        .offset(
            x: offset.width + dragTranslation.width,
            y: offset.height + dragTranslation.height
        )
    }

    private var resizeHandle: some View {
        ResizeCornerArc(cornerRadius: cornerRadius)
            .stroke(
                Color.white.opacity(resizeHovering ? 0.65 : 0.22),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: 42, height: 42)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { resizeHovering = hovering }
                #if os(macOS)
                if hovering { NSCursor.crosshair.push() } else { NSCursor.pop() }
                #endif
            }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .updating($resizeTranslation) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        size = CGSize(
                            width: min(max(size.width + value.translation.width, minSize.width), maxSize.width),
                            height: min(max(size.height + value.translation.height, minSize.height), maxSize.height)
                        )
                    }
            )
            .help("Drag to resize")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))

            Text(title)
                .font(.headline.weight(.semibold))

            Spacer()

            Capsule()
                .fill(.white.opacity(0.24))
                .frame(width: 34, height: 5)

            if let onMinimize {
                Button(action: onMinimize) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Minimise \(title)")
                .accessibilityLabel("Minimise \(title)")
            } else if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close \(title)")
                .accessibilityLabel("Close \(title)")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .gesture(
            // Global space so the moving panel doesn't distort the translation (true 1:1).
            DragGesture(coordinateSpace: .global)
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation
                }
                .updating($isDragging) { _, state, _ in
                    state = true
                }
                .onEnded { value in
                    var next = CGSize(
                        width: offset.width + value.translation.width,
                        height: offset.height + value.translation.height
                    )
                    if let snapStep {
                        next = CGSize(
                            width: max(0, (next.width / snapStep).rounded() * snapStep),
                            height: max(0, (next.height / snapStep).rounded() * snapStep)
                        )
                    }
                    offset = next
                }
        )
    }
}

public extension View {
    func darkPanelControl() -> some View {
        self
            .tint(.white)
            .foregroundStyle(.white)
    }
}
