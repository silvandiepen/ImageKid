import SwiftUI

struct EmptyStateView: View {
    let isDropTarget: Bool
    let openAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 900 || proxy.size.height < 620
            let panelRect = CGRect(origin: .zero, size: proxy.size)

            ZStack {
                panelBackground(size: panelRect.size, isDropTarget: isDropTarget)
                    .frame(width: panelRect.width, height: panelRect.height)
                    .position(x: panelRect.midX, y: panelRect.midY)

                dropZone(compact: compact)
                    .frame(
                        width: compact ? min(560, panelRect.width * 0.54) : panelRect.width * 0.52,
                        height: compact ? panelRect.height * 0.48 : panelRect.height * 0.48
                    )
                    .position(
                        x: panelRect.midX,
                        y: panelRect.midY
                    )

                if let character = ImageKidAsset.image(named: "ImageKidCharacter") {
                    Image(nsImage: character)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: compact ? panelRect.width * 0.36 : panelRect.width * 0.42,
                            height: compact ? panelRect.height * 0.84 : panelRect.height * 0.92
                        )
                        .position(
                            x: panelRect.minX + panelRect.width * (compact ? 0.23 : 0.25),
                            y: panelRect.maxY - panelRect.height * (compact ? 0.33 : 0.30)
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func panelBackground(size: CGSize, isDropTarget: Bool) -> some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.065, blue: 0.10),
                    Color(red: 0.015, green: 0.018, blue: 0.026)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            AnimatedBottomWave(isDropTarget: isDropTarget)
                .frame(height: min(isDropTarget ? 260 : 150, size.height * (isDropTarget ? 0.36 : 0.22)))
                .opacity(isDropTarget ? 0.48 : 0.34)
                .animation(.easeOut(duration: 0.24), value: isDropTarget)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func dropZone(compact: Bool) -> some View {
        Button(action: openAction) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(isDropTarget ? 0.16 : 0.04))
                    .shadow(
                        color: isDropTarget ? Color(red: 0.14, green: 0.58, blue: 0.85).opacity(0.45) : .clear,
                        radius: isDropTarget ? 22 : 0
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isDropTarget ? Color(red: 0.14, green: 0.58, blue: 0.85) : .white.opacity(0.16),
                                lineWidth: isDropTarget ? 2 : 1
                            )
                    )

                VStack(spacing: compact ? 16 : 20) {
                    Text(isDropTarget ? "Let it go" : "Drop your image here")
                        .font(.system(size: compact ? 32 : 42, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("Jpg, Png, WebP and more up to 50mb")
                        .font(.system(size: compact ? 15 : 17, weight: .semibold))
                        .foregroundStyle(Color(red: 0.04, green: 0.55, blue: 0.83))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, compact ? 22 : 34)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .animation(.easeOut(duration: 0.16), value: isDropTarget)
    }
}

private struct AnimatedBottomWave: View {
    let isDropTarget: Bool

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottom) {
                WaveShape(phase: phase * 0.48, amplitude: isDropTarget ? 22 : 16)
                    .fill(Color(red: 0.08, green: 0.48, blue: 0.70).opacity(0.46))
            }
        }
    }
}

private struct WaveShape: Shape {
    let phase: Double
    let amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.minY + rect.height * 0.34
        path.move(to: CGPoint(x: rect.minX, y: midY))

        let step = max(rect.width / 72, 8)
        var x = rect.minX
        while x <= rect.maxX + step {
            let progress = (x - rect.minX) / max(rect.width, 1)
            let y = midY
                + sin(progress * .pi * 2.0 + phase) * amplitude
                + sin(progress * .pi * 4.0 + phase * 0.72) * amplitude * 0.28
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
