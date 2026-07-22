import SwiftUI

struct ViewportToolbar: View {
    @ObservedObject var session: ImageSession
    let displayedScale: CGFloat
    @Binding var isCollapsed: Bool
    var onEditSize: () -> Void = {}
    @State private var isShowingZoomMenu = false
    @State private var customZoomPercent = 100

    var body: some View {
        HStack(spacing: isCollapsed ? 4 : 7) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isCollapsed.toggle()
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .frame(width: 24, height: 24)
            }
            .help(isCollapsed ? "Show View Controls" : "Hide View Controls")
            .accessibilityLabel(isCollapsed ? "Show View Controls" : "Hide View Controls")

            if isCollapsed {
                zoomButton
            } else {
            Button(action: onEditSize) {
                Text(sizeLabel)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 104, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Resize / upscale…")

            Divider()
                .frame(height: 20)

            Button {
                session.zoom = max(0.1, session.zoom / 1.2)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                        .frame(width: 22, height: 22)
            }
            .help("Zoom Out")
            .accessibilityLabel("Zoom Out")

            zoomButton

            Button {
                session.zoom = min(12, session.zoom * 1.2)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                        .frame(width: 22, height: 22)
            }
            .help("Zoom In")
            .accessibilityLabel("Zoom In")

            Button {
                session.resetView()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                        .frame(width: 22, height: 22)
            }
            .help("Reset View")
            .accessibilityLabel("Reset View")

            Divider()
                .frame(height: 20)

                Button {
                    cycleViewportMode()
                } label: {
                    Image(systemName: viewportModeSymbol)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 28, height: 24)
                        .background(
                            Color.accentColor.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .help("View Mode: \(session.viewportMode.label)")
                .accessibilityLabel("View Mode: \(session.viewportMode.label)")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, isCollapsed ? 8 : 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.10))
        )
        .shadow(color: .black.opacity(0.14), radius: 14, y: 5)
    }

    private var zoomButton: some View {
        Button {
            customZoomPercent = visibleZoomPercent
            isShowingZoomMenu = true
        } label: {
            Text("\(visibleZoomPercent)%")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .frame(width: 54)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.secondary)
        .help("Set Zoom")
        .accessibilityLabel("Set Zoom")
        .popover(isPresented: $isShowingZoomMenu, arrowEdge: .top) {
            zoomPopover
        }
    }

    private var zoomPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 6)], spacing: 6) {
                ForEach([25, 50, 75, 100, 150, 200, 300, 400], id: \.self) { percent in
                    Button("\(percent)%") {
                        setVisibleZoomPercent(percent)
                        isShowingZoomMenu = false
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 8) {
                TextField("Zoom", value: customZoomBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 86)
                    .onSubmit { isShowingZoomMenu = false }
                Text("%")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 232)
    }

    private var sizeLabel: String {
        let size = session.effectivePixelSize
        return "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px"
    }

    private var visibleZoomPercent: Int {
        Int((displayedScale * session.zoom * 100).rounded())
    }

    private var customZoomBinding: Binding<Int> {
        Binding(
            get: { customZoomPercent },
            set: { percent in
                customZoomPercent = min(max(percent, 10), 1200)
                setVisibleZoomPercent(customZoomPercent)
            }
        )
    }

    private func setVisibleZoomPercent(_ percent: Int) {
        let clampedPercent = min(max(percent, 10), 1200)
        customZoomPercent = clampedPercent
        session.zoom = CGFloat(clampedPercent) / max(displayedScale * 100, 1)
    }

    private var viewportModeSymbol: String {
        switch session.viewportMode {
        case .contain:
            "rectangle.arrowtriangle.2.inward"
        case .cover:
            "rectangle.arrowtriangle.2.outward"
        case .original:
            "1.magnifyingglass"
        }
    }

    private func cycleViewportMode() {
        switch session.viewportMode {
        case .contain:
            session.viewportMode = .cover
        case .cover:
            session.viewportMode = .original
        case .original:
            session.viewportMode = .contain
        }
        session.zoom = 1
        session.pan = .zero
    }
}
