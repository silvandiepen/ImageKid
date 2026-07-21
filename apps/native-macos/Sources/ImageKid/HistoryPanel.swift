import SwiftUI

/// A named, jump-to-any-step history timeline (Photoshop-style). The current
/// step is highlighted; steps after it are dimmed and redoable.
struct HistoryPanel: View {
    @ObservedObject var session: ImageSession
    @Binding var offset: CGSize
    let onClose: () -> Void

    var body: some View {
        FloatingToolPanel(
            title: "History",
            systemImage: "clock.arrow.circlepath",
            width: 280,
            offset: $offset,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(session.historyIndex + 1) of \(session.history.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.58))
                    Spacer()
                    Button("Undo") { session.undo() }
                        .buttonStyle(.borderless)
                        .disabled(!session.canUndo)
                    Button("Redo") { session.redo() }
                        .buttonStyle(.borderless)
                        .disabled(!session.canRedo)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(session.history.enumerated()), id: \.element.id) { index, entry in
                                row(index: index, entry: entry)
                                    .id(index)
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: session.historyIndex) { _, newValue in
                        withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                    }
                }
            }
        }
    }

    private func row(index: Int, entry: ImageSession.HistoryEntry) -> some View {
        let isCurrent = index == session.historyIndex
        let isFuture = index > session.historyIndex
        return Button {
            session.jump(to: index)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22)
                Text(entry.name)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                Spacer()
                Text("\(index)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isCurrent ? Color.accentColor.opacity(0.30) : Color.white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .opacity(isFuture ? 0.4 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
