import SwiftUI

struct OperationProgressBar: View {
    let progress: OperationProgress?
    let fallbackTitle: String
    let currentDate: Date
    @Binding var offset: CGSize

    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        HStack(spacing: 14) {
            icon

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Text(progress?.title ?? fallbackTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    stepBadge

                    Spacer(minLength: 8)

                    if let progress {
                        Text(elapsedLabel(from: progress.startedAt, to: currentDate))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                }

                HStack(spacing: 10) {
                    progressRail

                    Text(percentLabel)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(width: 38, alignment: .trailing)
                }

                if let detail = progress?.detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .frame(width: 420)
        .background(
            Color.black.opacity(0.82),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        )
        .shadow(color: .black.opacity(0.34), radius: 24, y: 10)
        .offset(
            x: offset.width + dragTranslation.width,
            y: offset.height + dragTranslation.height
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .gesture(
            DragGesture()
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    offset = CGSize(
                        width: offset.width + value.translation.width,
                        height: offset.height + value.translation.height
                    )
                }
        )
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(iconColor.opacity(0.18))

            if progress?.fraction == nil {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
        }
        .frame(width: 42, height: 42)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.10))
        )
    }

    private var stepBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: stepIconName)
                .font(.system(size: 10, weight: .bold))
            Text(stepLabel)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white.opacity(0.72))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.09), in: Capsule())
    }

    private var progressRail: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.10))

                if let fraction = progress?.fraction {
                    Capsule()
                        .fill(iconColor)
                        .frame(width: max(8, proxy.size.width * min(max(fraction, 0), 1)))
                } else {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.12), iconColor.opacity(0.72), .white.opacity(0.12)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * 0.42)
                        .offset(x: proxy.size.width * 0.18)
                }
            }
        }
        .frame(height: 7)
    }

    private var percentLabel: String {
        guard let fraction = progress?.fraction else { return "..." }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    private var iconName: String {
        let detail = progress?.detail.lowercased() ?? fallbackTitle.lowercased()
        if detail.contains("background") { return "person.crop.rectangle" }
        if detail.contains("checking") || detail.contains("looked weird") { return "checkmark.seal" }
        if detail.contains("putting") || detail.contains("edges") { return "sparkles" }
        if detail.contains("again") || detail.contains("lighter") { return "arrow.triangle.2.circlepath" }
        return "arrow.up.left.and.arrow.down.right"
    }

    private var stepIconName: String {
        let detail = progress?.detail.lowercased() ?? ""
        if detail.contains("ready") || detail.contains("measuring") || detail.contains("finding") { return "scope" }
        if detail.contains("stretching") || detail.contains("sharp") { return "wand.and.stars" }
        if detail.contains("checking") || detail.contains("looked weird") { return "checkmark.circle" }
        if detail.contains("again") || detail.contains("lighter") { return "arrow.triangle.2.circlepath" }
        if detail.contains("putting") || detail.contains("edges") { return "sparkles" }
        return "gearshape"
    }

    private var stepLabel: String {
        let detail = progress?.detail.lowercased() ?? ""
        if detail.contains("ready") || detail.contains("measuring") || detail.contains("finding") { return "Scouting" }
        if detail.contains("stretching") { return "Stretching" }
        if detail.contains("sharp") { return "Polishing" }
        if detail.contains("checking") || detail.contains("looked weird") { return "Inspecting" }
        if detail.contains("again") || detail.contains("lighter") { return "Retrying" }
        if detail.contains("putting") || detail.contains("edges") { return "Finishing" }
        return "Working"
    }

    private var iconColor: Color {
        let detail = progress?.detail.lowercased() ?? fallbackTitle.lowercased()
        if detail.contains("background") { return .green }
        if detail.contains("again") || detail.contains("weird") || detail.contains("lighter") { return .orange }
        return .blue
    }

    private func elapsedLabel(from startDate: Date, to currentDate: Date) -> String {
        let seconds = max(0, Int(currentDate.timeIntervalSince(startDate).rounded()))
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}
