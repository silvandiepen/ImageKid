import SwiftUI

struct FloatingToolPanel<Content: View>: View {
    let title: String
    let systemImage: String
    let width: CGFloat
    @Binding var offset: CGSize
    let onClose: (() -> Void)?
    let onMinimize: (() -> Void)?
    let snapStep: CGFloat?
    let resizable: Bool
    @Binding var size: CGSize
    let content: Content

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var resizeTranslation: CGSize = .zero

    init(
        title: String,
        systemImage: String,
        width: CGFloat = 300,
        offset: Binding<CGSize>,
        onClose: (() -> Void)? = nil,
        onMinimize: (() -> Void)? = nil,
        snapStep: CGFloat? = nil,
        resizable: Bool = false,
        size: Binding<CGSize> = .constant(.zero),
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
        self.content = content()
    }

    private var resolvedWidth: CGFloat {
        guard resizable else { return width }
        return max(DockablePanel.minSize.width, size.width + resizeTranslation.width)
    }

    private var resolvedHeight: CGFloat? {
        guard resizable else { return nil }
        return max(DockablePanel.minSize.height, size.height + resizeTranslation.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(.white.opacity(0.09))
                .frame(height: 1)

            content
                .padding(16)
                .frame(maxHeight: resizable ? .infinity : nil, alignment: .top)
        }
        .frame(width: resolvedWidth, height: resolvedHeight, alignment: .top)
        .foregroundStyle(.white)
        .background(
            Color.black.opacity(0.80),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .overlay(alignment: .bottomTrailing) {
            if resizable { resizeHandle }
        }
        .shadow(color: .black.opacity(0.36), radius: 28, y: 12)
        .offset(
            x: offset.width + dragTranslation.width,
            y: offset.height + dragTranslation.height
        )
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.4))
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($resizeTranslation) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        size = CGSize(
                            width: min(max(size.width + value.translation.width, DockablePanel.minSize.width), DockablePanel.maxSize.width),
                            height: min(max(size.height + value.translation.height, DockablePanel.minSize.height), DockablePanel.maxSize.height)
                        )
                    }
            )
            .help("Resize")
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
            DragGesture()
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation
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

extension View {
    func darkPanelControl() -> some View {
        self
            .tint(.white)
            .foregroundStyle(.white)
    }
}
