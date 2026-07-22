import AppKit
import SwiftUI

/// Photoshop-style foreground / background colour chips with a swap control.
/// Foreground is the default stroke/text colour; background the default fill.
struct ForegroundBackgroundChips: View {
    @ObservedObject var library: ColorLibrary

    enum Slot { case foreground, background }
    @State private var editing: Slot?

    var body: some View {
        ZStack(alignment: .topLeading) {
            chip(color: library.background, slot: .background)
                .offset(x: 13, y: 13)
            chip(color: library.foreground, slot: .foreground)

            Button {
                library.swapForegroundBackground()
            } label: {
                Image(systemName: "arrow.2.squarepath")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.black.opacity(0.7), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .offset(x: 22, y: -3)
            .help("Swap foreground and background")
        }
        .frame(width: 40, height: 38)
        .popover(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }), arrowEdge: .bottom) {
            editor
        }
    }

    private func chip(color: NSColor, slot: Slot) -> some View {
        Button {
            editing = slot
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: color))
                .frame(width: 24, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help(slot == .foreground ? "Foreground colour" : "Background colour")
    }

    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing == .background ? "Background" : "Foreground")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ColorPicker("Colour", selection: slotBinding, supportsOpacity: true)
                .labelsHidden()

            BaseSwatchStrip(colors: library.baseColors) { picked in
                setSlot(picked)
            }

            HStack {
                Button("Swap") { library.swapForegroundBackground() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Reset") {
                    if editing == .background { library.background = .white } else { library.foreground = .black }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(width: 232)
    }

    private var slotBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: editing == .background ? library.background : library.foreground) },
            set: { setSlot(NSColor($0)) }
        )
    }

    private func setSlot(_ color: NSColor) {
        if editing == .background { library.background = color } else { library.foreground = color }
    }
}
