import AppKit
import ImageKidCore
import ImageKidKit
import SwiftUI

/// Photoshop-style foreground / background colour chips with a swap control.
/// Foreground is the default stroke/text colour; background the default fill.
struct ForegroundBackgroundChips: View {
    @ObservedObject var library: ColorLibrary
    @ObservedObject var session: ImageSession

    enum Slot { case foreground, background }
    @State private var editing: Slot?

    /// The selected annotation (shape OR text) the chips act on, if any. For text
    /// the "foreground" is the text colour.
    private var selectedShape: Annotation? {
        session.selectedAnnotation
    }

    private var currentForeground: NSColor {
        selectedShape?.strokeColor ?? library.foreground
    }

    private var currentBackground: NSColor {
        if let shape = selectedShape, shape.isFillable { return shape.fillColor ?? .clear }
        return library.background
    }

    /// Which well the rail is acting on. ImageKid has no persistent notion of
    /// an "active" paint the way Fekthor does, so foreground leads.
    @State private var active: PaintWellSlot = .primary

    var body: some View {
        // Shared with Fekthor — see PaintWellsBar in ImageKidKit.
        PaintWellsBar(
            active: $active,
            primaryHelp: "Foreground",
            secondaryHelp: "Background",
            onEdit: { slot in editing = slot == .primary ? .foreground : .background },
            onSwap: swap,
            primary: {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: currentForeground))
            },
            secondary: {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: currentBackground))
            }
        )
        .popover(
            isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }),
            arrowEdge: .trailing
        ) {
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
                Button("Swap") { swap() }
                    .buttonStyle(.bordered)
                Spacer()
                if editing == .background, selectedShape?.isFillable == true {
                    Button("No fill") { setBackground(nil) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .frame(width: 232)
    }

    private var slotBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: editing == .background ? currentBackground : currentForeground) },
            set: { setSlot(NSColor($0)) }
        )
    }

    private func setSlot(_ color: NSColor) {
        if editing == .background { setBackground(color) } else { setForeground(color) }
    }

    private func setForeground(_ color: NSColor) {
        library.foreground = color
        if let shape = selectedShape {
            session.updateAnnotation(id: shape.id) { $0.strokeColor = color }
        }
    }

    private func setBackground(_ color: NSColor?) {
        if let color { library.background = color }
        if let shape = selectedShape, shape.isFillable {
            session.updateAnnotation(id: shape.id) { $0.fillColor = color }
        }
    }

    private func swap() {
        if let shape = selectedShape, shape.isFillable {
            let stroke = shape.strokeColor
            let fill = shape.fillColor
            session.updateAnnotation(id: shape.id) {
                $0.strokeColor = fill ?? .clear
                $0.fillColor = stroke
            }
        } else {
            library.swapForegroundBackground()
        }
    }
}
