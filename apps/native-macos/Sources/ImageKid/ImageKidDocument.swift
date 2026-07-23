import AppKit
import Foundation
import ImageKidCore

// The document format and DTOs live in ImageKidCore (shared with iOS). This
// file bridges the portable document to the macOS ImageSession editor.

extension ImageKidDocument {
    @MainActor
    init?(session: ImageSession) {
        guard let base = IKImageCoder.encode(session.sourceImage) else { return nil }
        self.init(
            baseImage: base,
            backgroundRemovedImage: session.backgroundRemovedImage.flatMap { IKImageCoder.encode($0) },
            cropRect: IKRect(session.cropRect),
            outputSize: session.outputSize.map(IKSize.init),
            viewportMode: session.viewportMode.rawValue,
            grid: IKGrid(
                show: session.showGrid, snap: session.snapToGrid, size: session.gridSizePx,
                colorHex: session.gridColorHex, opacity: session.gridOpacity, subdivisions: session.gridSubdivisions
            ),
            annotations: session.annotations.map(IKAnnotation.init),
            imageLayers: session.imageLayers.compactMap(IKLayer.init),
            layerGroups: session.layerGroups.map(IKGroup.init),
            baseUnlocked: session.baseUnlocked
        )
    }

    /// Rebuild a live session from the document.
    @MainActor
    func makeSession() -> ImageSession? {
        guard let base = IKImageCoder.decode(baseImage) else { return nil }
        let session = ImageSession(sourceURL: nil, sourceImage: base)
        session.backgroundRemovedImage = IKImageCoder.decode(backgroundRemovedImage)
        session.cropRect = cropRect.cg
        session.outputSize = outputSize?.cg
        session.viewportMode = ViewportMode(rawValue: viewportMode) ?? .contain
        session.showGrid = grid.show
        session.snapToGrid = grid.snap
        session.gridSizePx = grid.size
        session.gridColorHex = grid.colorHex
        session.gridOpacity = grid.opacity
        session.gridSubdivisions = grid.subdivisions
        session.annotations = annotations.map(\.annotation)
        session.imageLayers = imageLayers.compactMap(\.layer)
        session.layerGroups = layerGroups.map(\.group)
        session.baseUnlocked = baseUnlocked ?? false
        session.seedHistory()
        return session
    }
}
