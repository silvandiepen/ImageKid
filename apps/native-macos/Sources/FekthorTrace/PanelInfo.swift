import SwiftUI

/// The palettes' help mechanic: a tiny "i" next to a section title that
/// opens the explanation in a popover, instead of caption paragraphs
/// burning palette height. Every palette that needs more than a couple of
/// words of help should use one of these.
struct PanelInfoButton: View {
    let text: String

    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("About this section")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 220, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
        }
    }
}
