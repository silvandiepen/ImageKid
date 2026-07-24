import SwiftUI

/// The shared "nothing open yet" screen for ImageKid and Fekthor.
///
/// Both apps render the *same* layout — character bottom-left, copy and
/// action cards on the right — and differ only in their title, their cards,
/// their accent and their character art. Keep changes here rather than
/// forking per app, or the two drift apart again.

public struct HomeAction: Identifiable {
    public let id: String
    public let icon: String
    public let title: String
    public let subtitle: String
    public let enabled: Bool
    public let action: () -> Void

    public init(
        id: String,
        icon: String,
        title: String,
        subtitle: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.enabled = enabled
        self.action = action
    }
}

public struct HomeLink: Identifiable {
    public let id: String
    public let title: String
    public let action: () -> Void

    public init(id: String, title: String, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.action = action
    }
}

public struct HomeScreen<Recents: View>: View {
    private let title: String
    private let subtitle: String
    private let footnote: String
    private let character: Image?
    /// width ÷ height of the character art. Needed so the figure can be sized
    /// from the space actually left beside the copy, whatever its proportions.
    private let characterAspect: CGFloat
    private let accent: Color
    private let actions: [HomeAction]
    private let links: [HomeLink]
    private let highlighted: Bool
    private let recents: () -> Recents

    public init(
        title: String,
        subtitle: String,
        footnote: String,
        character: Image?,
        characterAspect: CGFloat = 0.6,
        accent: Color,
        actions: [HomeAction],
        links: [HomeLink] = [],
        highlighted: Bool = false,
        @ViewBuilder recents: @escaping () -> Recents
    ) {
        self.title = title
        self.subtitle = subtitle
        self.footnote = footnote
        self.character = character
        self.characterAspect = characterAspect
        self.accent = accent
        self.actions = actions
        self.links = links
        self.highlighted = highlighted
        self.recents = recents
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // Below this the character crowds the cards, so it steps aside.
            // Copy column is fixed; the character gets whatever is left, so
            // the two can never collide however wide the art is.
            let columnWidth: CGFloat = 560
            let trailing: CGFloat = 60
            let leading: CGFloat = 40
            let gap: CGFloat = 32
            let characterBudget = size.width - columnWidth - trailing - leading - gap
            let stacked = size.width < 820 || size.height < 560 || characterBudget < 190

            ZStack {
                HomeBackground(highlighted: highlighted)

                if stacked {
                    content(centered: true)
                        .padding(40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        content(centered: false)
                            .frame(maxWidth: columnWidth)
                            .padding(.trailing, trailing)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    characterView(
                        height: min(size.height * 1.10, characterBudget / characterAspect, 1180)
                    )
                    .padding(.leading, leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        highlighted ? accent.opacity(0.9) : .white.opacity(0.07),
                        lineWidth: highlighted ? 2.5 : 1
                    )
            )
            .animation(.easeOut(duration: 0.22), value: highlighted)
        }
    }

    // MARK: - Character

    /// Deliberately oversized and pushed past the bottom edge so the feet
    /// crop — it reads as standing in the window rather than floating in it.
    private func characterView(height: CGFloat) -> some View {
        Group {
            if let character {
                character
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
                    .shadow(color: .black.opacity(highlighted ? 0.45 : 0.35), radius: 38, y: 14)
                    .rotationEffect(.degrees(highlighted ? -2.5 : 0), anchor: .bottom)
                    .scaleEffect(highlighted ? 1.03 : 1, anchor: .bottom)
            }
        }
        .frame(height: height, alignment: .bottom)
        .offset(y: height * 0.12)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: highlighted)
    }

    // MARK: - Content

    private func content(centered: Bool) -> some View {
        let alignment: HorizontalAlignment = centered ? .center : .leading
        let textAlign: TextAlignment = centered ? .center : .leading

        return VStack(alignment: alignment, spacing: 22) {
            VStack(alignment: alignment, spacing: 6) {
                Text(title)
                    .font(.figtree(size: 40, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(textAlign)
                Text(subtitle)
                    .font(.figtree(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(textAlign)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                ForEach(actions) { action in
                    HomeCard(action: action, accent: accent, highlighted: highlighted)
                        .accessibilityIdentifier(action.id)
                }
            }

            if !links.isEmpty {
                HStack(spacing: 20) {
                    ForEach(links) { link in
                        Button(link.title, action: link.action)
                            .buttonStyle(.link)
                    }
                }
            }

            recents()

            Text(footnote)
                .font(.figtree(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

// MARK: - Card

private struct HomeCard: View {
    let action: HomeAction
    let accent: Color
    let highlighted: Bool

    @State private var hovering = false

    var body: some View {
        Button(action: action.action) {
            VStack(spacing: 9) {
                Image(systemName: action.icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(action.enabled ? accent : Color.white.opacity(0.4))
                Text(action.title)
                    .font(.figtree(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text(action.subtitle)
                    .font(.figtree(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(width: 168, height: 148)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(fill))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(!action.enabled)
        .opacity(action.enabled ? 1 : 0.6)
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    private var fill: Double {
        if highlighted { return 0.12 }
        return hovering ? 0.11 : 0.06
    }
}

// MARK: - Recents

/// "Recent" heading plus rows. Both apps use this so their lists match; only
/// the row accessory differs (a workspace preview grid vs an image thumbnail).
public struct HomeRecentsSection<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.figtree(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.bottom, 1)
            content()
        }
    }
}

/// One recent row: accessory thumbnail, name, secondary line.
public struct HomeRecentRow<Accessory: View>: View {
    private let title: String
    private let detail: String
    private let help: String?
    private let action: () -> Void
    private let accessory: () -> Accessory

    @State private var hovering = false

    public init(
        title: String,
        detail: String,
        help: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.help = help
        self.action = action
        self.accessory = accessory
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                accessory()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.figtree(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.figtree(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.10 : 0.045))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help ?? "")
    }
}

// MARK: - Background

/// Translucent by design: the window material and whatever is behind it show
/// through, so the screen sits on the app's glass rather than covering it.
public struct HomeBackground: View {
    public var highlighted: Bool
    public var opacity: Double

    public init(highlighted: Bool = false, opacity: Double = 0.62) {
        self.highlighted = highlighted
        self.opacity = opacity
    }

    public var body: some View {
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

            // Cool glow, lower left — brightens while a file hovers
            RadialGradient(
                colors: [
                    Color(red: 0.24, green: 0.52, blue: 0.80)
                        .opacity(highlighted ? 0.42 : 0.26),
                    .clear
                ],
                center: .init(x: 0.18, y: 0.88),
                startRadius: 0,
                endRadius: 560
            )
            .animation(.easeOut(duration: 0.3), value: highlighted)
        }
        .opacity(opacity)
        .overlay(FloatingStars())
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
            Color(red: 0.95, green: 0.91, blue: 0.84),
            Color(red: 0.34, green: 0.66, blue: 0.96),
            Color(red: 0.93, green: 0.54, blue: 0.21)
        ]
        // Deterministic scatter across the panel.
        let seeds: [(CGFloat, CGFloat, CGFloat)] = [
            (0.08, 0.16, 14), (0.15, 0.62, 9), (0.21, 0.34, 7), (0.27, 0.82, 11),
            (0.34, 0.12, 8), (0.41, 0.48, 6), (0.44, 0.72, 13), (0.52, 0.22, 10),
            (0.57, 0.60, 7), (0.63, 0.38, 9), (0.68, 0.86, 12), (0.72, 0.14, 8),
            (0.78, 0.52, 14), (0.83, 0.30, 6), (0.88, 0.70, 10), (0.92, 0.44, 8),
            (0.95, 0.18, 12), (0.12, 0.90, 7), (0.49, 0.90, 9), (0.60, 0.08, 11)
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
