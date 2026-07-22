import AppKit
import FekthorKit
import SwiftUI

/// The Transform palette: numeric position (X/Y of the selection box
/// origin), absolute size (W/H with a lock-aspect chain), and apply-once
/// rotate / skew fields — every operation lands in the GEOMETRY through
/// TransformOps (never a CSS transform). Multi-selections act on the union
/// box: scale anchors on the box origin, rotate/skew on the common centre.
/// The Distort section enters the canvas's Free Distort mode (four
/// independently draggable corners, one "Distort" undo step on commit).
///
/// X/Y/W/H show current values and commit on Return; rotate and skew are
/// deltas — baked geometry has no stored angle — so they apply and reset.
struct TransformPanelContent: View {
    @ObservedObject var session: EditorSession

    @State private var xText = ""
    @State private var yText = ""
    @State private var wText = ""
    @State private var hText = ""
    @State private var lockAspect = true
    @State private var rotateText = ""
    @State private var skewXText = ""
    @State private var skewYText = ""

    private var box: (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        session.selectionBounds()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.selection.isEmpty {
                Text("Select something to transform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                positionRow
                sizeRow
                Divider()
                rotateRow
                skewRow
                Text("Skew converts shapes to paths")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Divider()
                distortSection
            }
        }
        .onAppear { sync() }
        .onChange(of: session.generation) { _, _ in sync() }
        .onChange(of: session.selection) { _, _ in sync() }
    }

    // MARK: Rows

    private var positionRow: some View {
        HStack(spacing: 8) {
            field("X", $xText) { commitPosition(x: $0) }
            field("Y", $yText) { commitPosition(y: $0) }
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 8) {
            field("W", $wText) { commitSize(width: $0) }
            field("H", $hText) { commitSize(height: $0) }
            Button {
                lockAspect.toggle()
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(
                        .white.opacity(lockAspect ? 0.28 : 0.08),
                        in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help(lockAspect ? "Unlock aspect ratio" : "Lock aspect ratio")
        }
    }

    private var rotateRow: some View {
        HStack(spacing: 8) {
            Text("Rotate")
                .font(.caption)
                .frame(width: 44, alignment: .leading)
            TextField("0", text: $rotateText)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .frame(width: 56)
                .onSubmit { commitRotate() }
            Text("°  applies around the centre")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var skewRow: some View {
        HStack(spacing: 8) {
            Text("Skew")
                .font(.caption)
                .frame(width: 44, alignment: .leading)
            TextField("0", text: $skewXText)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .frame(width: 56)
                .onSubmit { commitSkew(isX: true) }
            Text("X°")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("0", text: $skewYText)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .frame(width: 56)
                .onSubmit { commitSkew(isX: false) }
            Text("Y°")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var distortSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Distort")
                .font(.caption)
                .foregroundStyle(.secondary)
            if session.distort == nil {
                Button {
                    session.beginDistort()
                } label: {
                    Label("Free Distort", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Drag the selection's four corners independently (bilinear warp)")
            } else {
                Text("Drag the corner handles on the canvas")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Commit") { session.commitDistort() }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help("Keep the warp (Return)")
                    Button("Cancel") { session.cancelDistort() }
                        .font(.caption)
                        .controlSize(.small)
                        .help("Restore the shapes (Esc)")
                }
            }
        }
    }

    // MARK: Field plumbing

    private func field(
        _ label: String, _ text: Binding<String>, commit: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .leading)
            TextField("—", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .onSubmit {
                    if let v = Double(text.wrappedValue.trimmingCharacters(in: .whitespaces)) {
                        commit(v)
                    }
                    sync()
                }
        }
    }

    private func commitPosition(x: Double? = nil, y: Double? = nil) {
        session.moveSelectionTo(x: x, y: y)
    }

    private func commitSize(width: Double? = nil, height: Double? = nil) {
        guard let box else { return }
        let w = box.maxX - box.minX
        let h = box.maxY - box.minY
        var sx = 1.0
        var sy = 1.0
        if let width, width > 0, w > 1e-9 { sx = width / w }
        if let height, height > 0, h > 1e-9 { sy = height / h }
        if lockAspect {
            let s = width != nil ? sx : sy
            sx = s
            sy = s
        }
        session.scaleSelectionNumeric(sx: sx, sy: sy, around: Pt(box.minX, box.minY))
    }

    private func commitRotate() {
        if let d = Double(rotateText.trimmingCharacters(in: .whitespaces)) {
            session.rotateSelectionNumeric(degrees: d)
        }
        rotateText = ""
    }

    /// One skew field applies its axis alone; the other stays untouched.
    private func commitSkew(isX: Bool) {
        let text = isX ? skewXText : skewYText
        if let d = Double(text.trimmingCharacters(in: .whitespaces)) {
            session.skewSelection(xDegrees: isX ? d : 0, yDegrees: isX ? 0 : d)
        }
        if isX { skewXText = "" } else { skewYText = "" }
    }

    private func sync() {
        guard let box else {
            xText = ""
            yText = ""
            wText = ""
            hText = ""
            return
        }
        xText = Self.fieldText(box.minX)
        yText = Self.fieldText(box.minY)
        wText = Self.fieldText(box.maxX - box.minX)
        hText = Self.fieldText(box.maxY - box.minY)
    }

    private static func fieldText(_ v: Double) -> String {
        let rounded = (v * 100).rounded() / 100
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.2f", rounded)
    }
}
