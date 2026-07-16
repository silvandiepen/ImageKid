import SwiftUI

struct EmptyStateView: View {
    let isDropTarget: Bool
    let openAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 650 || proxy.size.width < 820

            ZStack {
                background

                VStack(spacing: 0) {
                    titleBar
                        .padding(.top, compact ? 15 : 20)

                    Spacer(minLength: compact ? 14 : 24)

                    dropZone(compact: compact)
                        .frame(
                            maxWidth: compact ? 620 : 720,
                            maxHeight: compact ? 445 : 580
                        )
                        .padding(.horizontal, compact ? 38 : 70)

                    Spacer(minLength: compact ? 24 : 54)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .preferredColorScheme(.dark)
    }

    private var background: some View {
        ZStack {
            Color(red: 0.045, green: 0.045, blue: 0.075)

            RadialGradient(
                colors: [Color.purple.opacity(0.12), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 520
            )

            LinearGradient(
                colors: [
                    Color.blue.opacity(0.025),
                    .clear,
                    Color.pink.opacity(0.028)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var titleBar: some View {
        HStack(spacing: 10) {
            ImageKidIcon()
                .frame(width: 28, height: 28)

            Text("ImageKid")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
    }

    private func dropZone(compact: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 28 : 34, style: .continuous)
                .fill(Color.black.opacity(isDropTarget ? 0.2 : 0.105))

            RoundedRectangle(cornerRadius: compact ? 28 : 34, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color.cyan,
                            Color.blue,
                            Color.purple,
                            Color.pink,
                            Color.orange,
                            Color.cyan
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(
                        lineWidth: isDropTarget ? 2.5 : 1.55,
                        lineCap: .round,
                        dash: [8, 10]
                    )
                )
                .opacity(isDropTarget ? 1 : 0.88)

            VStack(spacing: compact ? 12 : 16) {
                ImageKidHeroGraphic()
                    .frame(
                        width: compact ? 180 : 245,
                        height: compact ? 180 : 245
                    )
                    .scaleEffect(isDropTarget ? 1.045 : 1)

                Text(isDropTarget ? "Release to open" : "Drop an image here")
                    .font(.system(size: compact ? 31 : 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("or")
                    .font(.system(size: compact ? 17 : 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))

                Button(action: openAction) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: compact ? 19 : 22, weight: .semibold))

                        Text("Open Image")
                            .font(.system(size: compact ? 18 : 21, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, compact ? 34 : 46)
                    .padding(.vertical, compact ? 13 : 16)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.02, green: 0.52, blue: 1),
                                Color(red: 0.48, green: 0.08, blue: 0.96),
                                Color(red: 0.94, green: 0.08, blue: 0.5),
                                Color(red: 1, green: 0.35, blue: 0.12)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: Color.purple.opacity(0.28), radius: 18, y: 8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                Text("Drag and drop an image to get started.")
                    .font(.system(size: compact ? 14 : 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.top, compact ? 2 : 4)
            }
            .padding(.horizontal, compact ? 30 : 56)
            .padding(.vertical, compact ? 24 : 42)
        }
        .scaleEffect(isDropTarget ? 1.008 : 1)
        .shadow(
            color: isDropTarget ? Color.purple.opacity(0.22) : .clear,
            radius: 30
        )
        .animation(.easeOut(duration: 0.16), value: isDropTarget)
    }
}
