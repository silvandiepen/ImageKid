import AppKit
import FekthorKit
import SwiftUI

/// THE colour dot. One shape, one size, one border — used by the Swatches
/// palette, the swatch picker's grids and the colour wells in the style
/// palettes, so a colour looks the same everywhere it appears.
struct SwatchDot: View {
    let color: Color
    var size: CGFloat = 22
    /// Draws the accent ring (the picker marks the current colour).
    var isCurrent: Bool = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 5, style: .continuous) }

    var body: some View {
        shape
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                shape.strokeBorder(
                    isCurrent ? Color.accentColor : .white.opacity(0.25),
                    lineWidth: isCurrent ? 2 : 1)
            )
            .contentShape(shape)
    }
}

/// The editor's colour well: clicking opens a swatch-first popover — this
/// file's swatches, the workspace's shared swatches and the colours already
/// used in the document, as labelled grids — with "Custom…" (the system
/// picker) at the bottom. Swapped in wherever a paint is picked (Fill and
/// Stroke palettes, gradient stops) so colour picking is swatch-first
/// everywhere. The workspace session arrives via the environment (injected
/// on the panels layer); file-local swatches live on the EditorSession
/// (FileMeta) so a detached single file keeps its own set.
struct SwatchColorWell: View {
    @ObservedObject var session: EditorSession
    @EnvironmentObject var workspace: WorkspaceSession
    /// The colour the well shows (current paint, or black when unset).
    var current: Color
    /// nil hides the "+ add current" affordance (gradient stops pass the
    /// stop colour's hex; paint rows pass their summary hex).
    var addableHex: String? = nil
    var onPick: (Color) -> Void

    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            SwatchDot(color: current)
        }
        .buttonStyle(.plain)
        .help("Pick a colour (swatches first)")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            SwatchPickerPopover(
                session: session, workspace: workspace, current: current,
                addableHex: addableHex,
                onPick: { color in
                    onPick(color)
                })
        }
    }
}

/// The popover body: labelled swatch grids (file-local first, then
/// workspace, then the document's own colours) and the system picker.
private struct SwatchPickerPopover: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var workspace: WorkspaceSession
    var current: Color
    var addableHex: String?
    var onPick: (Color) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var custom: Color = .black

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section(
                title: "This file", hexes: session.fileSwatches,
                empty: "No file swatches yet.", addable: true)
            if workspace.workspace != nil {
                Divider()
                section(
                    title: "Workspace", hexes: workspace.settings.swatches ?? [],
                    empty: "No workspace swatches yet.", addable: false)
            }
            let used = documentColors
            if !used.isEmpty {
                Divider()
                section(title: "In this document", hexes: used, empty: "", addable: false)
            }
            Divider()
            ColorPicker(
                "Custom…",
                selection: Binding(
                    get: { custom },
                    set: { color in
                        custom = color
                        onPick(color)
                    }),
                supportsOpacity: false
            )
            .font(.caption)
        }
        .padding(12)
        .frame(width: 232)
        .onAppear { custom = current }
    }

    @ViewBuilder
    private func section(title: String, hexes: [String], empty: String, addable: Bool)
        -> some View
    {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if addable, let hex = addableHex, !session.fileSwatches.contains(hex) {
                    Button {
                        session.addFileSwatch(hex)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 18, height: 18)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("Add the current colour (\(hex)) to this file's swatches")
                }
            }
            if hexes.isEmpty {
                if !empty.isEmpty {
                    Text(empty).font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 22, maximum: 22), spacing: 6)],
                    alignment: .leading, spacing: 6
                ) {
                    ForEach(hexes, id: \.self) { hex in
                        swatch(hex, deletable: addable)
                    }
                }
            }
        }
    }

    private func swatch(_ hex: String, deletable: Bool) -> some View {
        Button {
            guard let c = PaintValue.parseHex(hex) else { return }
            onPick(
                Color(
                    red: Double(c.r) / 255, green: Double(c.g) / 255,
                    blue: Double(c.b) / 255))
            // A swatch click is ONE undo step (Swatches-palette semantics);
            // only the Custom picker's scrubbing coalesces.
            session.endStyleEdit()
            dismiss()
        } label: {
            SwatchDot(color: color(hex), isCurrent: color(hex) == current)
        }
        .buttonStyle(.plain)
        .help(hex)
        .contextMenu {
            if deletable {
                Button("Remove from File Swatches", role: .destructive) {
                    session.removeFileSwatch(hex)
                }
            }
        }
    }

    private func color(_ hex: String) -> Color {
        guard let c = PaintValue.parseHex(hex) else { return .black }
        return Color(
            red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    /// Unique plain colours used by the document's shapes, document order.
    private var documentColors: [String] {
        var seen: Set<String> = []
        var out: [String] = []
        func add(_ paint: PaintValue?) {
            guard case .color(let r, let g, let b)? = paint else { return }
            let hex = String(format: "#%02x%02x%02x", r, g, b)
            if seen.insert(hex).inserted { out.append(hex) }
        }
        func walk(_ nodes: [GraphicNode]) {
            for node in nodes {
                switch node {
                case .raw, .image: continue  // placed rasters carry no paint
                case .group(let g): walk(g.children)
                case .shape(let s):
                    let style = s.effectiveStyle
                    add(style.fill)
                    add(style.stroke)
                }
            }
        }
        walk(session.document.nodes)
        return out
    }
}
