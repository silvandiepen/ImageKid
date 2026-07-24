import BrushKit
import ImageKidKit
import InkaKit
import SwiftUI
import UIKit

/// Inka iPad root: the shared `HomeScreen` until a canvas is open, then the
/// Metal canvas with a compact brush/colour/size bar. Small by design — the P1
/// proof that the shared engine runs on iPad too.
struct ContentView: View {
    @StateObject private var model = InkaModel(document: .blank(width: 2048, height: 1536))
    @State private var hasCanvas = false
    @State private var shareImage: UIImage?

    var body: some View {
        Group {
            if hasCanvas { canvas } else { home }
        }
    }

    private var home: some View {
        HomeScreen(
            title: "Inka",
            subtitle: "Drawing and illustration, with a serious brush engine.",
            footnote: "a new canvas to start painting",
            character: nil,
            accent: .accentColor,
            actions: [
                HomeAction(
                    id: "inka.newCanvas", icon: "paintbrush.pointed.fill",
                    title: "New Canvas", subtitle: "2048 × 1536",
                    action: { newCanvas(width: 2048, height: 1536) }),
                HomeAction(
                    id: "inka.square", icon: "square",
                    title: "Square", subtitle: "1536 × 1536",
                    action: { newCanvas(width: 1536, height: 1536) }),
            ],
            recents: { EmptyView() })
    }

    private func newCanvas(width: Int, height: Int) {
        model.document = .blank(width: width, height: height)
        model.clearCanvas()
        hasCanvas = true
    }

    private var canvas: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            InkaCanvasView(model: model)
                .background(Color(white: 0.5))
        }
        .sheet(item: Binding(
            get: { shareImage.map(ShareItem.init) },
            set: { _ in shareImage = nil })
        ) { item in
            ShareSheet(items: [item.image])
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button { hasCanvas = false } label: { Image(systemName: "chevron.left") }
            Divider().frame(height: 22)
            ForEach(BrushLibrary.all) { brush in
                Button {
                    model.selectBrush(brush.id)
                } label: {
                    Image(systemName: brushIcon(brush))
                        .frame(width: 34, height: 30)
                        .background(
                            model.currentBrushID == brush.id
                                ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(model.currentBrushID == brush.id ? .white : .primary)
                }
            }
            Divider().frame(height: 22)
            ColorPicker("", selection: $model.color, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: model.color) { _, _ in model.syncRenderer() }
            Slider(value: $model.size, in: 1...200)
                .frame(width: 160)
                .onChange(of: model.size) { _, _ in model.syncRenderer() }
            Spacer()
            Button { model.clearCanvas() } label: { Image(systemName: "trash") }
            Button { shareImage = model.exportImage() } label: {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func brushIcon(_ brush: Brush) -> String {
        switch brush.id {
        case BrushLibrary.inkPen.id: return "pencil.tip"
        case BrushLibrary.pencil.id: return "pencil"
        case BrushLibrary.airbrush.id: return "paintbrush.pointed"
        case BrushLibrary.marker.id: return "highlighter"
        default: return "paintbrush"
        }
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
    init(_ image: UIImage) { self.image = image }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
