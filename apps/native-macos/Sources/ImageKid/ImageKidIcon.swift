import AppKit
import SwiftUI

struct ImageKidIcon: View {
    var body: some View {
        if let image = ImageKidAsset.image(named: "ImageKidAppIcon") {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            FallbackImageKidIcon()
        }
    }
}

enum ImageKidAsset {
    static func image(named name: String) -> NSImage? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif

        guard let url = bundle.url(forResource: name, withExtension: "png") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

private struct FallbackImageKidIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.055, green: 0.065, blue: 0.15),
                                Color(red: 0.11, green: 0.045, blue: 0.16),
                                Color(red: 0.055, green: 0.055, blue: 0.11)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                            .strokeBorder(.white.opacity(0.16), lineWidth: max(1, size * 0.006))
                    }

                ImageKidArtwork()
                    .padding(size * 0.11)

                sparkle(size: size * 0.045)
                    .position(x: size * 0.205, y: size * 0.38)

                sparkle(size: size * 0.024)
                    .position(x: size * 0.77, y: size * 0.25)

                Circle()
                    .fill(.white.opacity(0.92))
                    .frame(width: size * 0.017, height: size * 0.017)
                    .position(x: size * 0.82, y: size * 0.68)

                Circle()
                    .fill(Color.cyan.opacity(0.9))
                    .frame(width: size * 0.012, height: size * 0.012)
                    .position(x: size * 0.28, y: size * 0.23)
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .shadow(color: .black.opacity(0.42), radius: size * 0.07, y: size * 0.04)
        }
        .aspectRatio(1, contentMode: .fit)
        .drawingGroup()
    }

    private func sparkle(size: CGFloat) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .cyan.opacity(0.8), radius: size * 0.25)
    }
}

struct ImageKidHeroGraphic: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color.purple.opacity(0.32), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.52
                        )
                    )
                    .frame(width: size * 1.12, height: size * 0.7)
                    .blur(radius: size * 0.08)
                    .offset(y: size * 0.12)

                ImageKidArtwork()
                    .frame(width: size * 0.72, height: size * 0.72)
                    .shadow(color: Color.purple.opacity(0.38), radius: size * 0.08, y: size * 0.05)

                particle(color: .purple, diameter: size * 0.105)
                    .position(x: size * 0.12, y: size * 0.66)

                particle(color: .blue, diameter: size * 0.085)
                    .position(x: size * 0.86, y: size * 0.64)

                particle(color: .pink, diameter: size * 0.07)
                    .position(x: size * 0.84, y: size * 0.25)

                particle(color: .indigo, diameter: size * 0.045)
                    .position(x: size * 0.28, y: size * 0.17)

                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.08, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange, .pink],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .position(x: size * 0.17, y: size * 0.35)

                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.035, weight: .bold))
                    .foregroundStyle(.purple)
                    .position(x: size * 0.09, y: size * 0.45)

                Diamond()
                    .fill(.purple)
                    .frame(width: size * 0.026, height: size * 0.026)
                    .position(x: size * 0.39, y: size * 0.08)

                Diamond()
                    .fill(.orange.opacity(0.9))
                    .frame(width: size * 0.018, height: size * 0.018)
                    .position(x: size * 0.93, y: size * 0.47)
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .drawingGroup()
    }

    private func particle(color: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.95), color.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: diameter, height: diameter)
            .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
            .shadow(color: color.opacity(0.5), radius: diameter * 0.28)
    }
}

private struct ImageKidArtwork: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                card(
                    colors: [Color.blue, Color.indigo, Color.purple],
                    rotation: -12,
                    offset: CGSize(width: -size * 0.08, height: -size * 0.04),
                    opacity: 0.76,
                    size: size
                )

                card(
                    colors: [Color.purple, Color.pink, Color.red],
                    rotation: 10,
                    offset: CGSize(width: size * 0.08, height: size * 0.015),
                    opacity: 0.72,
                    size: size
                )

                frontCard(size: size)
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func card(
        colors: [Color],
        rotation: Double,
        offset: CGSize,
        opacity: Double,
        size: CGFloat
    ) -> some View {
        RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                    .strokeBorder(.white.opacity(0.28), lineWidth: max(1, size * 0.01))
            }
            .frame(width: size * 0.72, height: size * 0.72)
            .rotationEffect(.degrees(rotation))
            .offset(offset)
            .opacity(opacity)
    }

    private func frontCard(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.65, blue: 1),
                            Color(red: 0.31, green: 0.11, blue: 0.96),
                            Color(red: 0.95, green: 0.12, blue: 0.53),
                            Color(red: 1, green: 0.42, blue: 0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            MountainShape(
                leftHeight: 0.62,
                peakX: 0.42,
                peakY: 0.36,
                rightHeight: 0.77
            )
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.97), Color.pink.opacity(0.72), Color.orange.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .padding(size * 0.045)

            MountainShape(
                leftHeight: 0.86,
                peakX: 0.72,
                peakY: 0.62,
                rightHeight: 0.82
            )
            .fill(
                LinearGradient(
                    colors: [Color.orange.opacity(0.96), Color.red.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .padding(size * 0.045)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.yellow.opacity(0.98), Color.orange, Color.pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.19, height: size * 0.19)
                .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: max(1, size * 0.006)))
                .position(x: size * 0.57, y: size * 0.25)

            LinearGradient(
                colors: [.white.opacity(0.5), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .blendMode(.screen)
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                .strokeBorder(.white.opacity(0.42), lineWidth: max(1, size * 0.011))
        }
        .frame(width: size * 0.72, height: size * 0.72)
        .rotationEffect(.degrees(-1.5))
    }
}

private struct MountainShape: Shape {
    let leftHeight: CGFloat
    let peakX: CGFloat
    let peakY: CGFloat
    let rightHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * leftHeight))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * peakX, y: rect.minY + rect.height * peakY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * rightHeight))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

@MainActor
enum ImageKidIconRenderer {
    static func makeNSImage(size: CGFloat = 512) -> NSImage? {
        if let image = ImageKidAsset.image(named: "ImageKidAppIcon") {
            return roundedImage(from: image, size: size)
        }

        let rootView = ImageKidIcon()
            .frame(width: size, height: size)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(x: 0, y: 0, width: size, height: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return nil
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        let image = NSImage(size: CGSize(width: size, height: size))
        image.addRepresentation(representation)
        return image
    }

    private static func roundedImage(from sourceImage: NSImage, size: CGFloat) -> NSImage {
        let targetSize = CGSize(width: size, height: size)
        let targetRect = CGRect(origin: .zero, size: targetSize)
        let image = NSImage(size: targetSize)

        image.lockFocus()
        NSColor.clear.setFill()
        targetRect.fill()

        let path = NSBezierPath(
            roundedRect: targetRect,
            xRadius: size * 0.225,
            yRadius: size * 0.225
        )
        path.addClip()
        sourceImage.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1)
        image.unlockFocus()

        return image
    }
}
