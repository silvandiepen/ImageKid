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

                if stacked {
                    VStack(spacing: 20) {
                        Spacer(minLength: 0)
                        content(compact: true)
                        character(height: min(size.height * 0.42, 320))
                    }
                    .padding(.top, 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                } else {
                    HStack(alignment: .bottom, spacing: 0) {
                        character(height: min(size.height * 0.98, 660))
                            .frame(maxWidth: size.width * 0.44)
                            .padding(.leading, compact ? 20 : 44)

                        content(compact: compact)
                            .frame(maxWidth: 480)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding(.trailing, compact ? 30 : 60)
                            .padding(.vertical, 40)
                    }
                }
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

    private func character(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(0.32))
                .frame(width: height * 0.5, height: height * 0.06)
                .blur(radius: 26)
                .offset(y: -height * 0.01)

            if let character = ImageKidAsset.image(named: "ImageKidCharacter") {
                Image(nsImage: character)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
                    .shadow(color: Brand.blue.opacity(isDropTarget ? 0.5 : 0.28), radius: 40, y: 14)
                    .rotationEffect(.degrees(isDropTarget ? -2.5 : 0), anchor: .bottom)
                    .scaleEffect(isDropTarget ? 1.03 : 1, anchor: .bottom)
            } else {
                Image(systemName: "paintbrush.pointed.fill")
                    .font(.system(size: height * 0.4))
                    .foregroundStyle(Brand.blueBright)
                    .frame(height: height)
            }
        }
        .frame(height: height, alignment: .bottom)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isDropTarget)
        .allowsHitTesting(false)
    }

    // MARK: - Content

    private func content(compact: Bool) -> some View {
        let alignment: HorizontalAlignment = compact ? .center : .leading
        let textAlign: TextAlignment = compact ? .center : .leading

        return VStack(alignment: alignment, spacing: compact ? 18 : 24) {
            VStack(alignment: alignment, spacing: 12) {
                Text(isDropTarget ? "Drop it right here!" : "Let's make something.")
                    .font(.system(size: compact ? 32 : 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(textAlign)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Drop an image anywhere, or open one to remove backgrounds, upscale, edit with AI, and more.")
                    .font(.system(size: compact ? 14 : 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(textAlign)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
            }

            dropCard(compact: compact)

            capabilityChips(compact: compact)
        }
        .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
    }

    private func dropCard(compact: Bool) -> some View {
        Button(action: openAction) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Brand.blueBright, Brand.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 58, height: 58)
                        .shadow(color: Brand.blue.opacity(0.6), radius: 12, y: 5)
                    Image(systemName: isDropTarget ? "tray.and.arrow.down.fill" : "photo.badge.plus.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(isDropTarget ? "Release to open" : "Choose an image")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("JPG, PNG, WebP and more · up to 50 MB")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: 440)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isDropTarget ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isDropTarget ? Brand.blueBright : .white.opacity(0.14),
                        style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1.5, dash: isDropTarget ? [] : [7, 5])
                    )
            )
            .shadow(color: isDropTarget ? Brand.blueBright.opacity(0.4) : .clear, radius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Brand.ink.opacity(0.65))
                )
            }
        }
        .frame(maxWidth: 440)
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

            FloatingStars()
        }
        .ignoresSafeArea()
    }
}

private struct FloatingStars: View {
    private struct Star {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let color: Color
        let twinkleSpeed: Double
        let twinklePhase: Double
        let driftSpeed: Double
        let driftPhase: Double
        let driftAmount: CGFloat
    }

    private let stars: [Star] = {
        let palette: [Color] = [
            .white,
            EmptyStateView.Brand.cream,
            EmptyStateView.Brand.blueBright,
            EmptyStateView.Brand.orange
        ]
        // Deterministic scatter across the panel.
        let seeds: [(CGFloat, CGFloat, CGFloat)] = [
            (0.08, 0.16, 14), (0.15, 0.62, 9),  (0.21, 0.34, 7),  (0.27, 0.82, 11),
            (0.34, 0.12, 8),  (0.41, 0.48, 6),  (0.44, 0.72, 13), (0.52, 0.22, 10),
            (0.57, 0.60, 7),  (0.63, 0.38, 9),  (0.68, 0.86, 12), (0.72, 0.14, 8),
            (0.78, 0.52, 14), (0.83, 0.30, 6),  (0.88, 0.70, 10), (0.92, 0.44, 8),
            (0.95, 0.18, 12), (0.12, 0.90, 7),  (0.49, 0.90, 9),  (0.60, 0.08, 11)
        ]
        return seeds.enumerated().map { index, seed in
            Star(
                x: seed.0,
                y: seed.1,
                size: seed.2,
                color: palette[index % palette.count],
                twinkleSpeed: 0.6 + Double(index % 5) * 0.18,
                twinklePhase: Double(index) * 0.7,
                driftSpeed: 0.05 + Double(index % 4) * 0.03,
                driftPhase: Double(index) * 1.3,
                driftAmount: 10 + CGFloat(index % 4) * 6
            )
        }
    }()

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                ZStack {
                    ForEach(Array(stars.enumerated()), id: \.offset) { _, star in
                        let twinkle = 0.35 + 0.4 * (0.5 + 0.5 * sin(t * star.twinkleSpeed * .pi + star.twinklePhase))
                        let drift = sin(t * star.driftSpeed * .pi + star.driftPhase) * star.driftAmount
                        Image(systemName: "sparkle")
                            .font(.system(size: star.size, weight: .medium))
                            .foregroundStyle(star.color)
                            .opacity(twinkle)
                            .shadow(color: star.color.opacity(0.5), radius: star.size * 0.35)
                            .position(
                                x: proxy.size.width * star.x,
                                y: proxy.size.height * star.y + drift
                            )
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
