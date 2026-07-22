import AppKit
import FekthorKit
import SwiftUI
import UniformTypeIdentifiers

/// Drives import, downscaling, conversion and preview. Engine work runs off the
/// main actor; results are published back on the main actor.
@MainActor
final class ConversionModel: ObservableObject {
    @Published var sourceImage: NSImage?
    @Published var vectorImage: NSImage?
    @Published var mode: Mode = .auto
    @Published var resolvedMode: Mode = .shapes
    @Published var logoPreset: Bool = false
    @Published var autoColors: Bool = true
    @Published var autoColorMinFraction: Double = 0.004
    @Published var colors: Double = 16
    /// 0 = coarse (fewer nodes), 1 = fine (more detail). Maps to DP tolerance.
    @Published var detail: Double = 0.55
    @Published var simplicity: Double = 0.3
    /// Flatten strength (Shapes only): collapse shade families (same hue, different
    /// lightness) into flat colours. 0 = off (identical to the non-flatten pipeline).
    @Published var flatten: Double = 0
    /// ML part awareness (Vision instance masks) — Shapes only, opt-in.
    @Published var partAware: Bool = false
    /// Real-ESRGAN 4× enhancement for small sources (model optional, local).
    @Published var enhance: Bool = false
    @Published var enhanceAvailable: Bool = Enhance.isAvailable
    @Published var modelDownloading: Bool = false
    @Published var sourceIsSmall: Bool = false
    private var originalImage: RasterImage?
    @Published var smoothing: Double = 0.65
    /// Geometry-refinement straighten strength (0…1): near-straight runs collapse
    /// to single lines / axis-snapped primitives.
    @Published var straighten: Double = 0.5
    @Published var strokeWidthAuto: Bool = true
    @Published var strokeWidth: Double = 4.0
    /// Uniform width: every stroke shares the median width (per-stroke widths off).
    @Published var uniformStrokeWidth: Bool = false
    @Published var strokeSource: StrokeSource = .auto
    /// Stroke end-cap style (round/butt/square).
    @Published var strokeCap: LineCap = .round
    /// Opt-in taper: narrowing tails render as outline fills (default off).
    @Published var taper: Bool = false
    /// Opt-in variable width: swelling/thinning strokes become one smooth
    /// outline fill (Illustrator width-profile semantics, default off).
    @Published var variableWidth: Bool = false
    /// Line-colour override for strokes (both sources). Off = keep sampled/black.
    @Published var lineColorEnabled: Bool = false
    @Published var lineColor: Color = .black
    /// Working resolution (longest side). 0 = Auto: simple-palette images
    /// (logos, flat art) get 2048 — they are cheap and edge fidelity matters
    /// most there; everything else gets 1024.
    @Published var resolution: Int = 0
    private var simplePalette: Bool = false
    @Published var status: String = "Drop, open or paste an image."
    @Published var isBusy = false
    /// The current vector document (always live-editable in the vector pane).
    /// Bumped via editGeneration so the canvas invalidates on each change.
    var document: VectorDocument?
    @Published var editGeneration = 0
    /// Selected paths (multi-select: marquee, Cmd-click toggle). Anchor-level
    /// editing engages when exactly one path is selected.
    @Published var selectedElements: Set<Int> = []
    /// Coalesces colour-picker streams into one undo snapshot per selection.
    private var colorGestureActive = false
    /// Reconverting replaces the document; when manual edits exist the UI asks
    /// first (the pending action runs on confirmation).
    @Published var confirmReconvert = false
    private var pendingAction: (() -> Void)?
    /// Set by any anchor/handle edit: the SVG regenerates lazily on export.
    private var documentEdited = false
    /// Undo history for edit mode: one snapshot per drag gesture.
    private var undoStack: [VectorDocument] = []
    @Published var canUndo = false
    @Published var imageGeneration = 0

    // Structured result, shown in the inspector.
    @Published var hasResult = false
    /// Mode-aware overall quality (0…1), honest and comparable across all modes.
    @Published var overallQuality: Double = 0
    @Published var exactPct: Double = 0
    @Published var psnr: Double = 0
    @Published var fills = 0
    @Published var strokes = 0
    @Published var nodes = 0
    @Published var svgKB = 0
    @Published var sourceInfo: String = ""

    var controlsMode: Mode { mode == .auto ? resolvedMode : mode }

    /// The imported image, capped at 2048 so re-deriving working sizes is cheap.
    private var fullImage: RasterImage?
    private var originalLongest = 0
    private var workingImage: RasterImage?
    private var svg: String = ""
    private var generation = 0
    private var cachedAutoGeneration: Int?
    private var cachedAutoDetection: AutoMode.Detection?

    // MARK: Import

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            load(path: url.path)
        }
    }

    func load(path: String) {
        guard let img = try? RasterImage.load(path: path) else {
            status = "Could not decode that image."
            return
        }
        adopt(img, name: (path as NSString).lastPathComponent)
    }

    func paste() {
        let pb = NSPasteboard.general
        if let nsImage = NSImage(pasteboard: pb),
            let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let img = try? RasterImage.from(cgImage: cg)
        {
            adopt(img, name: "Pasted image")
            return
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], let url = urls.first {
            load(path: url.path)
            return
        }
        status = "Clipboard has no image."
    }

    private func adopt(_ img: RasterImage, name: String) {
        originalImage = img
        sourceIsSmall = max(img.width, img.height) <= Enhance.maxInputSide
        applySourcePipeline(name: name)
    }

    /// Original → optional ML enhancement (small sources) → capped full image.
    private func applySourcePipeline(name: String?) {
        guard let img = originalImage else { return }
        documentEdited = false
        var source = img
        if enhance, sourceIsSmall, let up = Enhance.upscale4x(img) { source = up }
        // Simple-palette probe (cheap, on a thumbnail): drives Auto resolution
        // and logo auto-detection.
        let probe = ColorQuantizer.quantizeAuto(
            source.scaled(maxDimension: 256), maxColors: 6, minFraction: 0.02)
        simplePalette = probe.palette.count <= 4
        originalLongest = max(source.width, source.height)
        fullImage = source.scaled(maxDimension: 2048)
        imageGeneration += 1
        cachedAutoGeneration = nil
        cachedAutoDetection = nil
        resolvedMode = .shapes
        deriveAndConvert(name: name)
    }

    func enhanceChanged() {
        applySourcePipeline(name: nil)
    }

    /// Explicit user action (privacy plan): download the optional 4× model
    /// from the owner's R2 bucket, then enable enhancement.
    func downloadEnhanceModel() {
        guard !modelDownloading else { return }
        modelDownloading = true
        status = "Downloading Real-ESRGAN model (33 MB)…"
        Task {
            do {
                try await ModelStore.download(.realESRGAN)
                await MainActor.run {
                    self.modelDownloading = false
                    self.enhanceAvailable = Enhance.isAvailable
                    self.status = "Model installed."
                    if self.enhance { self.applySourcePipeline(name: nil) }
                }
            } catch {
                await MainActor.run {
                    self.modelDownloading = false
                    self.status = "Model download failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Re-derive the working image at the current resolution and convert.
    private func deriveAndConvert(name: String? = nil) {
        guard let full = fullImage else { return }
        let effectiveResolution = resolution == 0 ? (simplePalette ? 2048 : 1024) : resolution
        let working = full.scaled(maxDimension: effectiveResolution)
        workingImage = working
        if let cg = working.cgImage() {
            sourceImage = NSImage(
                cgImage: cg, size: NSSize(width: working.width, height: working.height))
        }
        let scaleNote = originalLongest > working.width ? " (from \(originalLongest)px)" : ""
        sourceInfo = "\(working.width)×\(working.height)\(scaleNote)"
        if let name { status = "Loaded \(name)" }
        convert()
    }

    func resolutionChanged() {
        deriveAndConvert()
    }

    // MARK: Auto-tune

    /// Grid-search Detail/Simplicity/Smoothing on a thumbnail (engine-side
    /// `AutoTune.search`, scored by Quality) and move the sliders to the
    /// winner, then reconvert at full size.
    func autoTune() {
        if documentEdited {
            pendingAction = { [weak self] in self?.performAutoTune() }
            confirmReconvert = true
            return
        }
        performAutoTune()
    }

    private func performAutoTune() {
        guard let working = workingImage else { return }
        generation += 1
        let gen = generation
        isBusy = true
        status = "Auto-tuning…"
        let mode = self.mode
        let lineRGB: RGB? = lineColorEnabled ? Self.rgb(from: lineColor) : nil
        // Current settings as the base; the searched axes are overwritten by
        // every grid point anyway.
        let base = Fekthor.Options(
            colors: Int(colors), epsilon: 4.2 - 3.9 * detail,
            simplicity: simplicity, smoothing: smoothing, straighten: straighten,
            autoColors: autoColors, autoColorMinFraction: autoColorMinFraction,
            flatten: flatten, partAware: partAware,
            strokeWidth: strokeWidthAuto ? nil : strokeWidth,
            uniformStrokeWidth: uniformStrokeWidth, strokeSource: strokeSource,
            strokeCap: strokeCap, taper: taper, variableWidth: variableWidth,
            lineColor: lineRGB)
        Task.detached(priority: .userInitiated) {
            let outcome = AutoTune.search(working, mode: mode, base: base)
            await MainActor.run {
                guard gen == self.generation else { return }
                self.simplicity = outcome.options.simplicity
                self.smoothing = outcome.options.smoothing
                self.detail = min(1, max(0, (4.2 - outcome.options.epsilon) / 3.9))
                self.status = String(
                    format: "Auto-tuned for this image (trial score %.0f%%)",
                    outcome.score * 100)
                self.convert()
            }
        }
    }

    // MARK: New file

    /// A blank single-artboard vector file (saved as plain SVG). No raster
    /// source: the app goes straight to the Edit canvas.
    func newBlankDocument(size: Int = 1024) {
        sourceImage = nil
        vectorImage = nil
        originalImage = nil
        fullImage = nil
        workingImage = nil
        document = VectorDocument(width: size, height: size, elements: [])
        svg = SVGExport.toSVG(document!, smoothing: smoothing)
        hasResult = true
        documentEdited = false
        undoStack = []
        canUndo = false
        selectedElements = []
        fills = 0
        strokes = 0
        nodes = 0
        svgKB = 0
        imageGeneration += 1
        editGeneration += 1
        status = "New file · \(size)×\(size) — paste or trace to fill it; Export saves SVG."
    }

    // MARK: Convert

    /// Guarded entry: warns before discarding manual edits.
    func convert() {
        if documentEdited {
            pendingAction = { [weak self] in self?.performConvert() }
            confirmReconvert = true
            return
        }
        performConvert()
    }

    func confirmPendingAction() {
        documentEdited = false
        confirmReconvert = false
        pendingAction?()
        pendingAction = nil
    }

    func cancelPendingAction() {
        confirmReconvert = false
        pendingAction = nil
        status = "Kept your edits — settings changed but the vector was not re-converted."
    }

    private func performConvert() {
        guard let working = workingImage else { return }
        generation += 1
        let gen = generation
        isBusy = true
        let mode = self.mode
        let smoothing = self.smoothing
        // Higher Detail → finer curves (smaller DP tolerance).
        let eps = 4.2 - 3.9 * detail
        let lineRGB: RGB? = lineColorEnabled ? Self.rgb(from: lineColor) : nil
        let detection = mode == .auto ? resolveAutoMode(for: working) : nil
        let conversionMode = detection?.resolved ?? mode
        if let detection { resolvedMode = detection.resolved } else { resolvedMode = mode }
        // Flatten is a Shapes-only behaviour; never leak it into Strokes/Gradient or Auto
        // resolutions that are not Shapes.
        let flattenValue = conversionMode == .shapes ? flatten : 0
        // Auto + simple palette + shapes = a logo-class image: use logo-grade
        // parameters (tiny accents like an ® survive, crisper straightening)
        // without yanking the user's sliders or leaving Auto mode.
        let logoAuto = mode == .auto && conversionMode == .shapes && simplePalette
        let options = Fekthor.Options(
            colors: Int(colors), epsilon: logoAuto ? min(eps, 0.885) : eps,
            simplicity: logoAuto ? min(simplicity, 0.10) : simplicity,
            smoothing: logoAuto ? 0.35 : smoothing,
            straighten: logoAuto ? max(straighten, 0.80) : straighten,
            autoColors: autoColors,
            autoColorMinFraction: logoAuto ? 0.002 : autoColorMinFraction,
            flatten: flattenValue,
            partAware: conversionMode == .shapes && partAware,
            strokeWidth: strokeWidthAuto ? nil : strokeWidth,
            uniformStrokeWidth: uniformStrokeWidth, strokeSource: strokeSource,
            strokeCap: strokeCap, taper: taper, variableWidth: variableWidth,
            lineColor: lineRGB)
        let statusSuffix = logoAuto ? " · logo" : ""
        Task.detached(priority: .userInitiated) {
            do {
                let result = try Fekthor.convert(working, mode: conversionMode, options: options)
                // Render the preview crisply (~2048px) so zooming stays sharp.
                let displayScale = max(
                    1.0, 2048.0 / Double(max(working.width, working.height)))
                let preview = Rasterizer.render(
                    result.document, smoothing: smoothing, scale: displayScale)
                let cg = preview.cgImage()
                let w = preview.width
                let h = preview.height
                let fills = result.document.fillCount
                let strokes = result.document.strokeCount
                let nodes = result.document.nodeCount
                let m = result.metrics
                let overall = result.quality.overall
                let svg = result.svg
                let document = result.document
                let kb = svg.utf8.count / 1024
                let resolvedMode = result.resolvedMode
                await MainActor.run {
                    guard gen == self.generation else { return }
                    if let cg {
                        self.vectorImage = NSImage(cgImage: cg, size: NSSize(width: w, height: h))
                    }
                    self.svg = svg
                    self.document = document
                    self.undoStack = []
                    self.canUndo = false
                    self.selectedElements = []
                    self.colorGestureActive = false
                    self.editGeneration += 1
                    self.hasResult = true
                    self.overallQuality = overall
                    self.exactPct = m.exactPct
                    self.psnr = m.psnr
                    self.fills = fills
                    self.strokes = strokes
                    self.nodes = nodes
                    self.svgKB = kb
                    self.resolvedMode = resolvedMode
                    self.status =
                        mode == .auto
                        ? "Converted · auto→\(resolvedMode.rawValue)\(statusSuffix)"
                        : "Converted · \(mode.rawValue)"
                    self.isBusy = false
                }
            } catch {
                await MainActor.run {
                    guard gen == self.generation else { return }
                    self.vectorImage = nil
                    self.hasResult = false
                    self.status = "\(error)"
                    self.isBusy = false
                }
            }
        }
    }

    private func resolveAutoMode(for image: RasterImage) -> AutoMode.Detection {
        if cachedAutoGeneration == imageGeneration, let cachedAutoDetection {
            return cachedAutoDetection
        }
        let detection = AutoMode.detect(image)
        cachedAutoGeneration = imageGeneration
        cachedAutoDetection = detection
        return detection
    }

    // MARK: Export / drop

    // MARK: Node editing

    /// Snapshot the document at the start of a drag gesture (one undo step
    /// per gesture, not per mouse-move).
    func beginEditGesture() {
        guard let doc = document else { return }
        undoStack.append(doc)
        if undoStack.count > 50 { undoStack.removeFirst() }
        canUndo = true
    }

    func undoEdit() {
        guard let doc = undoStack.popLast() else { return }
        document = doc
        documentEdited = true
        canUndo = !undoStack.isEmpty
        editGeneration += 1
    }

    /// Break a stroke at an anchor: interior anchors split it into two
    /// strokes; any anchor of a closed stroke cuts the loop open.
    func breakAnchor(element: Int, path: Int, anchor: Int) {
        guard var doc = document, element < doc.elements.count,
            let parts = Editing.breakAt(doc.elements[element], path: path, anchor: anchor)
        else {
            status = "This point cannot be broken (line ends and fills cannot)."
            return
        }
        beginEditGesture()
        doc.elements.replaceSubrange(element...element, with: parts)
        document = doc
        documentEdited = true
        strokes = doc.strokeCount
        nodes = doc.nodeCount
        status = parts.count == 2 ? "Broke the line into two." : "Cut the loop open."
        editGeneration += 1
    }

    /// Merge the selected anchors into one point (and join two open stroke
    /// ends into a single stroke, or close a loop).
    func mergeAnchors(_ refs: [Editing.AnchorRef]) {
        guard refs.count >= 2, let doc = document else { return }
        beginEditGesture()
        let merged = Editing.merge(doc, refs: refs)
        document = merged
        documentEdited = true
        strokes = merged.strokeCount
        nodes = merged.nodeCount
        status = "Merged \(refs.count) points."
        editGeneration += 1
    }

    /// The selection as a standalone tight-artboard document.
    private func selectionSubDocument() -> VectorDocument? {
        guard let doc = document, !selectedElements.isEmpty else { return nil }
        return Editing.subDocument(doc, elements: Array(selectedElements))
    }

    /// Copy the selected paths to the pasteboard as an SVG snippet.
    func copySelectionSVG() {
        guard let sub = selectionSubDocument() else { return }
        let svg = SVGExport.toSVG(sub, smoothing: smoothing)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(svg, forType: .string)
        status = "Copied \(selectedElements.count) path(s) as SVG."
    }

    /// Copy the selected paths as a rendered PNG image.
    func copySelectionPNG() {
        guard let sub = selectionSubDocument() else { return }
        let scale = max(1.0, 1024.0 / Double(max(sub.width, sub.height)))
        let img = Rasterizer.render(sub, smoothing: smoothing, scale: scale)
        guard let cg = img.cgImage() else { return }
        let ns = NSImage(cgImage: cg, size: NSSize(width: img.width, height: img.height))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([ns])
        status = "Copied \(selectedElements.count) path(s) as an image."
    }

    /// Save the selected paths to their own SVG file.
    func exportSelectionSVG() {
        guard let sub = selectionSubDocument() else { return }
        let svg = SVGExport.toSVG(sub, smoothing: smoothing)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .xml]
        panel.nameFieldStringValue = "selection.svg"
        if panel.runModal() == .OK, let url = panel.url {
            try? svg.write(to: url, atomically: true, encoding: .utf8)
            status = "Exported selection."
        }
    }

    /// Delete every selected path from the document (Backspace).
    func deleteSelection() {
        guard var doc = document, !selectedElements.isEmpty else { return }
        beginEditGesture()
        let count = selectedElements.count
        for i in selectedElements.sorted(by: >) where i < doc.elements.count {
            doc.elements.remove(at: i)
        }
        document = doc
        documentEdited = true
        selectedElements = []
        fills = doc.fillCount
        strokes = doc.strokeCount
        nodes = doc.nodeCount
        status = count == 1 ? "Deleted 1 path." : "Deleted \(count) paths."
        editGeneration += 1
    }

    /// Recolour every selected path. Continuous colour-picker updates share
    /// ONE undo snapshot (taken on the first change for this selection).
    func setSelectionColor(_ color: Color) {
        guard var doc = document, !selectedElements.isEmpty else { return }
        if !colorGestureActive {
            beginEditGesture()
            colorGestureActive = true
        }
        let rgb = Self.rgb(from: color)
        for i in selectedElements where i < doc.elements.count {
            doc.elements[i] = Editing.setColor(doc.elements[i], to: rgb)
        }
        document = doc
        documentEdited = true
        editGeneration += 1
    }

    /// The colour shown in the picker: the first selected element's colour.
    var selectionColor: Color {
        guard let doc = document, let i = selectedElements.sorted().first,
            i < doc.elements.count
        else { return .black }
        let c = Editing.color(of: doc.elements[i])
        return Color(
            red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    func selectionChanged() {
        colorGestureActive = false
    }

    /// Unique colours present in the current vector (first 12, element order)
    /// — shown as swatches beside the default palette.
    var documentColors: [Color] {
        guard let doc = document else { return [] }
        var seen = Set<UInt32>()
        var out: [Color] = []
        for el in doc.elements {
            let c = Editing.color(of: el)
            let key = UInt32(c.r) << 16 | UInt32(c.g) << 8 | UInt32(c.b)
            if seen.insert(key).inserted {
                out.append(
                    Color(
                        red: Double(c.r) / 255, green: Double(c.g) / 255,
                        blue: Double(c.b) / 255))
            }
            if out.count >= 12 { break }
        }
        return out
    }

    /// Remove one anchor: end anchors shorten an open stroke, interior anchors
    /// merge their neighbouring segments (simpler path, tangents preserved).
    func removeAnchor(element: Int, path: Int, anchor: Int) {
        guard var doc = document, element < doc.elements.count,
            let removed = Editing.removeAnchor(doc.elements[element], path: path, anchor: anchor)
        else {
            status = "This point cannot be removed (path is already minimal)."
            return
        }
        beginEditGesture()
        doc.elements[element] = removed
        document = doc
        documentEdited = true
        nodes = doc.nodeCount
        status = "Removed point."
        editGeneration += 1
    }

    /// Insert an anchor on one element's outline at (path, segment, t) — as
    /// reported by `Editing.closestPoint(of:to:)` (⌘-click on a selected
    /// path). One undo step; the new anchor's index is `segment + 1`.
    func insertAnchor(element: Int, path: Int, segment: Int, t: Double) {
        guard var doc = document, element < doc.elements.count,
            let inserted = Editing.insertAnchor(
                doc.elements[element], path: path, segment: segment, t: t)
        else {
            status = "A point cannot be added here."
            return
        }
        beginEditGesture()
        doc.elements[element] = inserted
        document = doc
        documentEdited = true
        nodes = doc.nodeCount
        status = "Added point."
        editGeneration += 1
    }

    /// Move one cubic control handle of one element. `mirror` keeps the
    /// opposite handle collinear (smooth point).
    func moveHandle(
        element: Int, path: Int, segment: Int, kind: Editing.HandleKind, to: Pt,
        mirror: Bool = false
    ) {
        guard var doc = document, element < doc.elements.count else { return }
        doc.elements[element] = Editing.moveHandle(
            doc.elements[element], path: path, segment: segment, kind: kind, to: to,
            mirror: mirror)
        document = doc
        documentEdited = true
        editGeneration += 1
    }

    /// Move one anchor of one element; the edit canvas redraws immediately and
    /// the SVG/preview refresh when editing ends.
    func moveAnchor(element: Int, path: Int, anchor: Int, to: Pt) {
        guard var doc = document, element < doc.elements.count else { return }
        doc.elements[element] = Editing.move(
            doc.elements[element], path: path, anchor: anchor, to: to)
        document = doc
        documentEdited = true
        editGeneration += 1
    }

    /// The current SVG text, regenerated when manual edits exist so it
    /// always matches the canvas; nil while there is nothing to export.
    func currentSVGText() -> String? {
        if documentEdited, let doc = document {
            svg = SVGExport.toSVG(doc, smoothing: smoothing)
            svgKB = svg.utf8.count / 1024
            nodes = doc.nodeCount
            documentEdited = false
        }
        return svg.isEmpty ? nil : svg
    }

    /// Clears the trace session back to the empty state (used when a traced
    /// icon lands in a workspace, or when a workspace opens over a trace).
    func reset() {
        generation += 1
        sourceImage = nil
        vectorImage = nil
        originalImage = nil
        fullImage = nil
        workingImage = nil
        document = nil
        svg = ""
        hasResult = false
        documentEdited = false
        undoStack = []
        canUndo = false
        selectedElements = []
        colorGestureActive = false
        isBusy = false
        sourceInfo = ""
        status = "Drop, open or paste an image."
        imageGeneration += 1
        editGeneration += 1
    }

    func exportSVG() {
        // Edits happen live on the document; the SVG string is regenerated
        // here so exports always match the canvas.
        guard let svg = currentSVGText() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .xml]
        panel.nameFieldStringValue = "fekthor.svg"
        if panel.runModal() == .OK, let url = panel.url {
            try? svg.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in self.load(path: url.path) }
        }
        return true
    }

    /// Convert a SwiftUI `Color` to the engine's `RGB` (sRGB 8-bit).
    static func rgb(from color: Color) -> RGB {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return (
            UInt8((ns.redComponent * 255).rounded()),
            UInt8((ns.greenComponent * 255).rounded()),
            UInt8((ns.blueComponent * 255).rounded())
        )
    }

    func applyLogoPreset() {
        mode = .shapes
        autoColors = true
        autoColorMinFraction = 0.002
        simplicity = 0.10
        detail = 0.85
        straighten = 0.80
        smoothing = 0.35
        convert()
    }

    func loadLaunchArgumentIfPresent() {
        for arg in CommandLine.arguments.dropFirst()
        where FileManager.default.fileExists(atPath: arg) {
            load(path: arg)
            return
        }
    }
}
