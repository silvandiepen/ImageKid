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
    let stackEdges: (topFlat: Bool, bottomFlat: Bool)
    let dockEdges: (leadingFlat: Bool, trailingFlat: Bool)
    let isStackFollower: Bool
    let onDragChanged: ((CGSize) -> Void)?
    let onDragEnded: ((CGSize) -> Void)?
    let contentPadding: CGFloat
    let content: Content

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var resizeTranslation: CGSize = .zero
    @GestureState private var isDragging = false
    @State private var resizeHovering = false
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Chrome palette
    //
    // The panel used to be hardcoded dark: a black scrim with white content,
    // which looked wrong floating over a light canvas in ImageKid's light
    // mode. It now follows the colour scheme, so light mode gets a light
    // panel with dark ink. Fekthor is unaffected — it forces
    // .preferredColorScheme(.dark), so it keeps the dark chrome it was
    // designed around.

    /// The panel surface: near-white in light mode, near-black in dark.
    private var chromeFill: Color {
        colorScheme == .dark ? Color.black.opacity(0.80) : Color.white.opacity(0.94)
    }

    /// Ink and icons on the panel.
    private var chromeInk: Color {
        colorScheme == .dark ? .white : Color(white: 0.10)
    }

    /// A hairline that reads as an edge in both appearances.
    private var chromeBorder: Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.10)
    }

    /// Fills for separators, control backings and wells — a tint of the ink,
    /// so one set of opacities works in both appearances.
    private func chromeTint(_ opacity: Double) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(opacity)
            : Color.black.opacity(opacity * 0.75)
    }

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
        stackEdges: (topFlat: Bool, bottomFlat: Bool) = (false, false),
        dockEdges: (leadingFlat: Bool, trailingFlat: Bool) = (false, false),
        isStackFollower: Bool = false,
        onDragChanged: ((CGSize) -> Void)? = nil,
        onDragEnded: ((CGSize) -> Void)? = nil,
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
        self.stackEdges = stackEdges
        self.dockEdges = dockEdges
        self.isStackFollower = isStackFollower
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.contentPadding = contentPadding
        self.content = content()
    }

    /// Header control diameters: tight on macOS pointers, at least 44pt on touch.
    private var minimizeButtonSize: CGFloat {
        #if os(iOS)
        44
        #else
        24
        #endif
    }

    private var closeButtonSize: CGFloat {
        #if os(iOS)
        44
        #else
        28
        #endif
    }

    private var resizeHandleSize: CGFloat {
        #if os(iOS)
        44
        #else
        42
        #endif
    }

    private var resolvedWidth: CGFloat {
        guard resizable else { return width }
        return max(minSize.width, size.width + resizeTranslation.width)
    }

    private var resolvedHeight: CGFloat? {
        guard resizable else { return nil }
        return max(minSize.height, size.height + resizeTranslation.height)
    }

    /// True while the panel is stuck to another one (either edge on a stick
    /// line). Resizing is disabled for the duration — the stack owns the
    /// shared width, and a free-resized member would break the flush column.
    private var isStacked: Bool { stackEdges.topFlat || stackEdges.bottomFlat }

    /// The chrome shape: the normal corner radius, except on edges that sit
    /// on a stick line — between stacked panels (top/bottom) or flush against
    /// a dock edge (leading/trailing) — which flatten to 4pt so the stack
    /// reads as one fused column and an edge-stuck panel reads as docked.
    private var chromeShape: UnevenRoundedRectangle {
        func radius(_ flat: Bool) -> CGFloat { flat ? 4 : cornerRadius }
        return UnevenRoundedRectangle(
            topLeadingRadius: radius(stackEdges.topFlat || dockEdges.leadingFlat),
            bottomLeadingRadius: radius(stackEdges.bottomFlat || dockEdges.leadingFlat),
            bottomTrailingRadius: radius(stackEdges.bottomFlat || dockEdges.trailingFlat),
            topTrailingRadius: radius(stackEdges.topFlat || dockEdges.trailingFlat),
            style: .continuous)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(chromeTint(0.09))
                .frame(height: 1)

            content
                .padding(contentPadding)
                .frame(maxHeight: resizable ? .infinity : nil, alignment: .top)
        }
        .frame(width: resolvedWidth, height: resolvedHeight, alignment: .top)
        .foregroundStyle(chromeInk)
        .background(chromeFill, in: chromeShape)
        .overlay(
            chromeShape
                .strokeBorder(chromeBorder)
        )
        .overlay(alignment: .bottomTrailing) {
            if resizable && !isStacked { resizeHandle }
        }
        // A large blurred shadow re-rasterises every frame while dragging, which
        // is the main source of drag stutter — shrink it hard during a drag.
        // Stack followers keep only a soft shadow so the seam onto the panel
        // above doesn't read as a dark band across the fused column.
        .shadow(
            color: .black.opacity(
                colorScheme == .dark
                    ? (isDragging ? 0.28 : (isStackFollower ? 0.16 : 0.36))
                    : (isDragging ? 0.14 : (isStackFollower ? 0.08 : 0.18))),
            radius: isDragging ? 6 : (isStackFollower ? 10 : 28),
            y: isDragging ? 3 : (isStackFollower ? 4 : 12))
        .offset(
            x: offset.width + dragTranslation.width,
            y: offset.height + dragTranslation.height
        )
    }

    private var resizeHandle: some View {
        ResizeCornerArc(cornerRadius: cornerRadius)
            .stroke(
                chromeTint(resizeHovering ? 0.65 : 0.22),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: resizeHandleSize, height: resizeHandleSize)
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
                .background(chromeTint(0.10), in: RoundedRectangle(cornerRadius: 9))

            Text(title)
                .font(.headline.weight(.semibold))

            Spacer()

            Capsule()
                .fill(chromeTint(0.24))
                .frame(width: 34, height: 5)

            if let onMinimize {
                Button(action: onMinimize) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(chromeTint(0.10), in: Circle())
                        .frame(width: minimizeButtonSize, height: minimizeButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Minimise \(title)")
                .accessibilityLabel("Minimise \(title)")
            } else if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(chromeTint(0.10), in: Circle())
                        .frame(width: closeButtonSize, height: closeButtonSize)
                        .contentShape(Rectangle())
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
                .onChanged { value in
                    onDragChanged?(value.translation)
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
                    // After the resting offset settled (including grid snap),
                    // so hosts run stick detection against final positions.
                    onDragEnded?(value.translation)
                }
        )
    }
}

/// Tints a control to the panel's ink. Named for the dark chrome it was
/// written against; it now follows the colour scheme like the panel itself,
/// so the 14 call sites did not have to change.
private struct PanelControlTint: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    private var ink: Color { colorScheme == .dark ? .white : Color(white: 0.10) }

    func body(content: Content) -> some View {
        content
            .tint(ink)
            .foregroundStyle(ink)
    }
}

public extension View {
    func darkPanelControl() -> some View { modifier(PanelControlTint()) }
}

// MARK: - Panel palette for panel content
//
// Views hosted inside a FloatingToolPanel used to hardcode white ink and
// white-tinted fills, which only worked because the panel was always dark.
// These two semantics follow the colour scheme instead, so the same opacity
// scale reads correctly in both appearances.

public extension Color {
    /// Ink for text and icons inside a panel.
    static func panelInk(_ scheme: ColorScheme, _ opacity: Double = 1) -> Color {
        scheme == .dark
            ? Color.white.opacity(opacity)
            : Color(white: 0.10).opacity(opacity)
    }

    /// Fill for wells, rows and separators inside a panel. Light mode darkens
    /// slightly rather than lightening, so a "subtle lift" stays subtle.
    static func panelFill(_ scheme: ColorScheme, _ opacity: Double = 1) -> Color {
        scheme == .dark
            ? Color.white.opacity(opacity)
            : Color.black.opacity(opacity * 0.75)
    }
}
