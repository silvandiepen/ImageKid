import AppKit
import SwiftUI
import ImageKidKit

/// Background fill for a newly created document.
enum NewFileBackground: String, CaseIterable, Identifiable {
    case transparent, white, black
    var id: String { rawValue }
    var label: String {
        switch self {
        case .transparent: return "Transparent"
        case .white: return "White"
        case .black: return "Black"
        }
    }
    var fillColor: NSColor? {
        switch self {
        case .transparent: return nil
        case .white: return .white
        case .black: return .black
        }
    }
}

extension NSImage {
    /// A blank canvas of the given pixel size, optionally filled with a colour
    /// (nil = transparent).
    static func blankCanvas(pixelSize: CGSize, fill: NSColor?) -> NSImage {
        let w = max(1, Int(pixelSize.width.rounded()))
        let h = max(1, Int(pixelSize.height.rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            return NSImage(size: NSSize(width: w, height: h))
        }
        rep.size = NSSize(width: w, height: h)
        if let fill {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            fill.setFill()
            NSRect(x: 0, y: 0, width: w, height: h).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let image = NSImage(size: NSSize(width: w, height: h))
        image.addRepresentation(rep)
        return image
    }
}

/// Panel to create a new document: choose a size (prefilled from the clipboard
/// image if there is one) and a background. Usable from the workspace and the
/// welcome screen.
struct NewFilePanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var appModel: AppModel
    @State private var width: Int = 1000
    @State private var height: Int = 1000
    @State private var background: NewFileBackground = .transparent
    @State private var lockRatio = false
    @State private var ratio: CGFloat = 1
    @State private var usedClipboard = false

    private let presets: [(String, Int, Int)] = [
        ("Square", 1000, 1000),
        ("1080p", 1920, 1080),
        ("Portrait", 1080, 1350),
        ("4K", 3840, 2160),
        ("Icon", 1024, 1024)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            if usedClipboard { clipboardNote }
            sizeField
            presetsField
            backgroundField
            buttonsRow
        }
        .padding(20)
        .frame(width: 340)
        .foregroundStyle(Color.panelInk(colorScheme))
        .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.panelFill(colorScheme, 0.12)))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 14)
        .darkPanelControl()
        .onAppear(perform: prefillFromClipboard)
    }

    private var headerRow: some View {
        HStack {
            Label("New File", systemImage: "doc.badge.plus")
                .font(.headline.weight(.semibold))
            Spacer()
            Button {
                appModel.isShowingNewFile = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Color.panelFill(colorScheme, 0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var clipboardNote: some View {
        Label("Using the size of the image on your clipboard.", systemImage: "doc.on.clipboard")
            .font(.caption)
            .foregroundStyle(Color.panelInk(colorScheme, 0.6))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sizeField: some View {
        field("Size") {
            HStack(spacing: 8) {
                TextField("Width", value: widthBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("×").foregroundStyle(Color.panelInk(colorScheme, 0.5))
                TextField("Height", value: heightBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("px").foregroundStyle(Color.panelInk(colorScheme, 0.5))
                Spacer()
                Toggle(isOn: $lockRatio) {
                    Image(systemName: lockRatio ? "lock" : "lock.open")
                }
                .toggleStyle(.button)
                .help("Lock aspect ratio")
            }
        }
    }

    private var presetsField: some View {
        field("Presets") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                ForEach(presets, id: \.0) { preset in
                    presetButton(preset)
                }
            }
        }
    }

    private func presetButton(_ preset: (String, Int, Int)) -> some View {
        Button {
            width = preset.1
            height = preset.2
            ratio = CGFloat(preset.1) / CGFloat(preset.2)
        } label: {
            VStack(spacing: 2) {
                Text(preset.0).font(.caption.weight(.semibold))
                Text("\(preset.1)×\(preset.2)")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.panelInk(colorScheme, 0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color.panelFill(colorScheme, 0.075), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var backgroundField: some View {
        field("Background") {
            Picker("Background", selection: $background) {
                ForEach(NewFileBackground.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var buttonsRow: some View {
        HStack(spacing: 10) {
            Button("Cancel") { appModel.isShowingNewFile = false }
                .frame(maxWidth: .infinity)
            Button {
                appModel.newDocument(width: width, height: height, background: background)
            } label: {
                Text("Create").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func prefillFromClipboard() {
        if let size = appModel.clipboardImageSize() {
            width = max(1, Int(size.width.rounded()))
            height = max(1, Int(size.height.rounded()))
            ratio = size.height > 0 ? size.width / size.height : 1
            usedClipboard = true
        }
    }

    private var widthBinding: Binding<Int> {
        Binding(get: { width }, set: { newValue in
            width = max(1, newValue)
            if lockRatio { height = max(1, Int((CGFloat(width) / ratio).rounded())) }
        })
    }

    private var heightBinding: Binding<Int> {
        Binding(get: { height }, set: { newValue in
            height = max(1, newValue)
            if lockRatio { width = max(1, Int((CGFloat(height) * ratio).rounded())) }
        })
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.panelInk(colorScheme, 0.72))
            content()
        }
    }
}
