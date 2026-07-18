import SwiftUI

struct EmptyStateView: View {
    let isDropTarget: Bool
    let openAction: () -> Void

    fileprivate enum Brand {
        static let blue = Color(red: 0.24, green: 0.52, blue: 0.80)
        static let blueBright = Color(red: 0.34, green: 0.66, blue: 0.96)
        static let orange = Color(red: 0.93, green: 0.54, blue: 0.21)
        static let cream = Color(red: 0.95, green: 0.91, blue: 0.84)
        static let ink = Color(red: 0.043, green: 0.067, blue: 0.098)
        static let teal = Color(red: 0.075, green: 0.16, blue: 0.22)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let compact = size.width < 900 || size.height < 620
            let stacked = size.width < 720 || size.height < 540

            ZStack {
                EmptyStateBackground(isDropTarget: isDropTarget)

                Group {
                    if stacked {
                        VStack(spacing: 24) {
                            character(maxHeight: min(size.height * 0.34, 260))
                            content(compact: true)
                        }
                    } else {
                        HStack(alignment: .center, spacing: compact ? 28 : 52) {
                            character(maxHeight: min(size.height * 0.86, 520))
                                .frame(maxWidth: .infinity, alignment: .center)
                            content(compact: compact)
                                .frame(maxWidth: compact ? 380 : 440, alignment: .leading)
                        }
                    }
                }
                .padding(compact ? 30 : 56)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isDropTarget ? Brand.blueBright.opacity(0.9) : .white.opacity(0.07),
                        lineWidth: isDropTarget ? 2.5 : 1
                    )
            )
            .animation(.easeOut(duration: 0.22), value: isDropTarget)
        }
    }

    // MARK: - Character

    private func character(maxHeight: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(0.35))
                .frame(width: maxHeight * 0.62, height: maxHeight * 0.09)
                .blur(radius: 22)
                .offset(y: maxHeight * 0.02)

            if let character = ImageKidAsset.image(named: "ImageKidCharacter") {
                Image(nsImage: character)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
                    .shadow(color: Brand.blue.opacity(isDropTarget ? 0.5 : 0.28), radius: 34, y: 12)
                    .rotationEffect(.degrees(isDropTarget ? -2.5 : 0), anchor: .bottom)
                    .scaleEffect(isDropTarget ? 1.03 : 1, anchor: .bottom)
            } else {
                Image(systemName: "paintbrush.pointed.fill")
                    .font(.system(size: maxHeight * 0.4))
                    .foregroundStyle(Brand.blueBright)
                    .frame(height: maxHeight)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isDropTarget)
        .allowsHitTesting(false)
    }

    // MARK: - Content

    private func content(compact: Bool) -> some View {
        let alignment: HorizontalAlignment = compact ? .center : .leading
        let textAlign: TextAlignment = compact ? .center : .leading

        return VStack(alignment: alignment, spacing: compact ? 18 : 22) {
            VStack(alignment: alignment, spacing: 10) {
                HStack(spacing: 9) {
                    ImageKidIcon()
                        .frame(width: 26, height: 26)
                    Text("ImageKid")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .tracking(0.5)
                }

                Text(isDropTarget ? "Drop it right here!" : "Let's make something.")
                    .font(.system(size: compact ? 30 : 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(textAlign)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Drop an image anywhere, or open one to remove backgrounds, upscale, edit with AI, and more.")
                    .font(.system(size: compact ? 14 : 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(textAlign)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }

            dropCard(compact: compact)

            capabilityChips(compact: compact)
        }
        .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
    }

    private func dropCard(compact: Bool) -> some View {
        Button(action: openAction) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Brand.blueBright, Brand.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                        .shadow(color: Brand.blue.opacity(0.6), radius: 10, y: 4)
                    Image(systemName: isDropTarget ? "tray.and.arrow.down.fill" : "photo.badge.plus.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(isDropTarget ? "Release to open" : "Choose an image")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("JPG, PNG, WebP and more · up to 50 MB")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isDropTarget ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isDropTarget ? Brand.blueBright : .white.opacity(0.14),
                        style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1.5, dash: isDropTarget ? [] : [7, 5])
                    )
            )
            .shadow(color: isDropTarget ? Brand.blueBright.opacity(0.4) : .clear, radius: 20)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .keyboardShortcut(.defaultAction)
    }

    private func capabilityChips(compact: Bool) -> some View {
        let items: [(String, String)] = [
            ("scissors", "Remove background"),
            ("wand.and.stars", "AI edit"),
            ("arrow.up.left.and.arrow.down.right", "Upscale"),
            ("crop", "Crop & resize")
        ]

        return FlowLayout(spacing: 8, lineSpacing: 8, alignment: compact ? .center : .leading) {
            ForEach(items, id: \.1) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.0)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Brand.orange)
                    Text(item.1)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: 380)
    }
}

// MARK: - Background

private struct EmptyStateBackground: View {
    let isDropTarget: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.075, green: 0.13, blue: 0.19),
                    Color(red: 0.035, green: 0.055, blue: 0.085),
                    Color(red: 0.02, green: 0.03, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Warm glow, upper right
            RadialGradient(
                colors: [Color(red: 0.93, green: 0.54, blue: 0.21).opacity(0.22), .clear],
                center: .init(x: 0.82, y: 0.14),
                startRadius: 0,
                endRadius: 520
            )

            // Cool glow, lower left — brightens when a file hovers
            RadialGradient(
                colors: [Color(red: 0.24, green: 0.52, blue: 0.80).opacity(isDropTarget ? 0.42 : 0.26), .clear],
                center: .init(x: 0.18, y: 0.88),
                startRadius: 0,
                endRadius: 560
            )
            .animation(.easeOut(duration: 0.3), value: isDropTarget)

            FloatingPaintDots()
                .opacity(0.55)
        }
        .ignoresSafeArea()
    }
}

private struct FloatingPaintDots: View {
    private struct Dot {
        let x: CGFloat
        let size: CGFloat
        let color: Color
        let speed: Double
        let phase: Double
        let travel: CGFloat
    }

    private let dots: [Dot] = [
        .init(x: 0.14, size: 10, color: EmptyStateView.Brand.blueBright, speed: 0.09, phase: 0.0, travel: 26),
        .init(x: 0.30, size: 6, color: EmptyStateView.Brand.orange, speed: 0.13, phase: 1.7, travel: 18),
        .init(x: 0.62, size: 8, color: EmptyStateView.Brand.cream, speed: 0.07, phase: 3.1, travel: 30),
        .init(x: 0.78, size: 5, color: EmptyStateView.Brand.blueBright, speed: 0.15, phase: 0.9, travel: 20),
        .init(x: 0.90, size: 9, color: EmptyStateView.Brand.orange, speed: 0.10, phase: 2.4, travel: 24)
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                ZStack {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                        let baseY = proxy.size.height * (0.2 + dot.phase.truncatingRemainder(dividingBy: 0.6))
                        let drift = sin(t * dot.speed * .pi + dot.phase) * dot.travel
                        Circle()
                            .fill(dot.color)
                            .frame(width: dot.size, height: dot.size)
                            .blur(radius: 0.5)
                            .opacity(0.35)
                            .position(x: proxy.size.width * dot.x, y: baseY + drift)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Button style

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Flow layout (wraps chips to available width)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var rowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let addition = rows.last!.isEmpty ? size.width : rowWidth + spacing + size.width
            if addition > maxWidth, !rows.last!.isEmpty {
                rows.append([size])
                rowWidth = size.width
            } else {
                rows[rows.count - 1].append(size)
                rowWidth = addition
            }
        }

        let width = rows.map { row in
            row.reduce(0) { $0 + $1.width } + CGFloat(max(0, row.count - 1)) * spacing
        }.max() ?? 0
        let height = rows.reduce(CGFloat(0)) { partial, row in
            partial + (row.map(\.height).max() ?? 0)
        } + CGFloat(max(0, rows.count - 1)) * lineSpacing

        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var rows: [[LayoutSubviews.Element]] = [[]]
        var sizes: [[CGSize]] = [[]]
        var rowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let addition = rows.last!.isEmpty ? size.width : rowWidth + spacing + size.width
            if addition > maxWidth, !rows.last!.isEmpty {
                rows.append([subview])
                sizes.append([size])
                rowWidth = size.width
            } else {
                rows[rows.count - 1].append(subview)
                sizes[sizes.count - 1].append(size)
                rowWidth = addition
            }
        }

        var y = bounds.minY
        for (rowIndex, row) in rows.enumerated() {
            let rowSizes = sizes[rowIndex]
            let rowContentWidth = rowSizes.reduce(0) { $0 + $1.width } + CGFloat(max(0, row.count - 1)) * spacing
            let rowHeight = rowSizes.map(\.height).max() ?? 0

            var x: CGFloat
            switch alignment {
            case .center: x = bounds.minX + (maxWidth - rowContentWidth) / 2
            case .trailing: x = bounds.minX + (maxWidth - rowContentWidth)
            default: x = bounds.minX
            }

            for (i, subview) in row.enumerated() {
                subview.place(
                    at: CGPoint(x: x, y: y + (rowHeight - rowSizes[i].height) / 2),
                    proposal: ProposedViewSize(rowSizes[i])
                )
                x += rowSizes[i].width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }
}
