# Technical architecture

## Goals

The architecture must provide exact pixel inspection, smooth native media viewing, reversible edits, deterministic full-resolution export, bounded-memory local AI inference, and frame-accurate video processing.

## Platform

- Swift 6
- SwiftUI application lifecycle and command system
- AppKit precision canvas through `NSViewRepresentable`
- Core Graphics and Core Image for image rendering and effects
- Core ML for bundled model inference
- AVFoundation for video reading, playback, timing, audio, and writing
- VideoToolbox for hardware-assisted encoding where available
- Image I/O for image decoding, metadata, profiles, and encoding
- Uniform Type Identifiers for file support

Apple Silicon is the primary AI performance target. General viewing and editing may support Intel Macs if the eventual deployment target and benchmarks remain acceptable.

## Suggested structure

```text
ImageKid/
├── App/
│   ├── ImageKidApp.swift
│   ├── AppCommands.swift
│   └── AppSettings.swift
├── Domain/
│   ├── MediaSession.swift
│   ├── MediaAsset.swift
│   ├── MediaMetadata.swift
│   ├── EditState.swift
│   ├── Annotation.swift
│   ├── SampledColor.swift
│   ├── ResizeConfiguration.swift
│   ├── UpscaleConfiguration.swift
│   └── ExportConfiguration.swift
├── Canvas/
│   ├── MediaCanvasView.swift
│   ├── MediaCanvasRepresentable.swift
│   ├── CanvasController.swift
│   ├── CoordinateConverter.swift
│   ├── ViewportState.swift
│   ├── HitTesting.swift
│   ├── SelectionRenderer.swift
│   └── ColorLoupe.swift
├── Imaging/
│   ├── ImageLoader.swift
│   ├── ImagePreviewGenerator.swift
│   ├── PixelSampler.swift
│   ├── PaletteExtractor.swift
│   ├── ImageRenderer.swift
│   └── ImageExporter.swift
├── Video/
│   ├── VideoAssetController.swift
│   ├── VideoFrameReader.swift
│   ├── VideoPreviewProvider.swift
│   ├── VideoRenderer.swift
│   ├── AudioPipeline.swift
│   └── VideoExporter.swift
├── Upscaling/
│   ├── UpscalingEngine.swift
│   ├── CoreMLUpscalingEngine.swift
│   ├── ModelManifest.swift
│   ├── ModelRegistry.swift
│   ├── TilePlanner.swift
│   ├── TileBlender.swift
│   ├── ImageUpscalePipeline.swift
│   └── VideoUpscalePipeline.swift
├── Annotations/
│   ├── AnnotationRenderer.swift
│   ├── AnnotationInteraction.swift
│   ├── TextAnnotationEditor.swift
│   └── StrokeSimplifier.swift
├── Infrastructure/
│   ├── FileAccessService.swift
│   ├── PasteboardService.swift
│   ├── RecentFilesService.swift
│   ├── RecoveryStore.swift
│   └── ProcessActivityController.swift
└── Tests/
```

## Session model

A window owns one `MediaSession`.

```swift
@MainActor
@Observable
final class MediaSession {
    let id: UUID
    var asset: MediaAsset
    var viewport: ViewportState
    var playback: PlaybackState?
    var editState: EditState
    var annotations: [Annotation]
    var selection: Set<UUID>
    var sampledColors: [SampledColor]
    var activeTool: Tool
    var exportConfiguration: ExportConfiguration
    var dirtyState: DirtyState
}
```

Large image buffers, video frames, and model objects are not stored directly in observable UI state. Services own immutable or synchronised resources.

## Media asset

`MediaAsset` is an enum or protocol-backed type for image and video assets. Both expose orientation-normalised dimensions, colour information, metadata, preview generation, pixel-frame access, and duration when relevant.

The source remains immutable. Crop, resize, upscale choice, and annotations are stored as edit intent.

## Coordinate systems

The app must explicitly model:

1. encoded source coordinates;
2. orientation-normalised source pixel coordinates;
3. working coordinates after crop and target sizing;
4. video frame coordinates;
5. canvas coordinates;
6. view coordinates;
7. Retina backing pixels.

`CoordinateConverter` is the only authority for conversion. It must support source-to-view and view-to-source point and rectangle conversion, crop offsets, output scaling, and exact pixel lookup.

Annotation geometry is stored in orientation-normalised source-relative coordinates. UI handles remain constant in view space.

## Annotation model

```swift
struct Annotation: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: AnnotationKind
    var opacity: Double
    var timeRange: MediaTimeRange?
    var isHidden: Bool
}
```

For images, `timeRange` is nil. For videos, nil or the complete duration means always visible. Geometry does not animate in the first release.

## Image preview and export

### Preview

1. Decode an orientation-correct preview sized for the display.
2. Apply crop and standard resize preview transforms.
3. Use an AI preview generated for a bounded selected region when requested.
4. Draw media, effects, and vector annotations.
5. Draw selection, crop, and loupe UI in view space.

### Export

1. Resolve crop against full-resolution source pixels.
2. Run standard resize or tiled AI inference.
3. Apply region effects from source-level pixels.
4. Render annotations at output scale.
5. apply the requested colour profile and metadata policy.
6. Encode atomically through Image I/O.

Never export a screenshot of the window.

## Video playback

Use `AVPlayer` or a dedicated AVFoundation playback abstraction for normal viewing. Precise colour sampling and frame stepping require a decoded frame provider whose timestamp corresponds to the displayed frame.

The canvas should use a stable pixel buffer or image representation while paused. Playback and precision tools must not race over ownership of the displayed frame.

## Video processing pipeline

Use a streaming pipeline:

1. `AVAssetReader` reads video sample buffers in presentation order.
2. Frame transforms normalise orientation and convert to the model’s required pixel format.
3. Crop, standard resize, or AI upscale is applied.
4. Visible annotations and region effects are composited for the frame timestamp.
5. `AVAssetWriter` writes the processed frame with its intended presentation timestamp.
6. Audio is passed through when container and codec compatibility allow; otherwise it is decoded and re-encoded locally.
7. Output is finalised atomically and moved to the user-selected URL only on success.

Do not materialise an entire clip as individual image files unless a fallback path is explicitly required and bounded.

## Upscaling interface

```swift
protocol UpscalingEngine: Sendable {
    var manifest: ModelManifest { get }

    func upscale(
        input: PixelBuffer,
        scale: UpscaleScale,
        options: UpscaleOptions
    ) async throws -> PixelBuffer
}
```

The first engine is `CoreMLUpscalingEngine`. The protocol exists to separate product state from model implementation, not to support cloud providers.

## Tiling

Full-resolution images and video frames may exceed model or device memory limits.

`TilePlanner` determines:

- input tile size;
- model-required alignment;
- overlap width;
- safe concurrency based on memory and device;
- edge padding;
- output crop for every tile.

`TileBlender` removes overlap using deterministic feathering or valid-region cropping. Tests must detect seams and tile-dependent colour shifts.

## Model lifecycle

- Models are signed resources in the application bundle.
- Xcode compiles Core ML packages for deployment.
- `ModelRegistry` loads manifests and models lazily.
- The application validates manifest version and checksum in development and release testing.
- Models are reused across requests and released under memory pressure where safe.
- Runtime model downloads are prohibited.

## Colour management

- Keep the embedded source profile.
- Render previews through colour-managed Core Image or Core Graphics contexts.
- Default copied colour values are converted to sRGB.
- Preserve or convert the profile on export according to user choice.
- Video frame conversion from YCbCr to RGB must use the correct matrix, transfer function, range, and primaries from attachments or track metadata.
- HDR video support is deferred until the complete processing and export path can preserve it correctly.

## Concurrency

- Session and UI mutation are `@MainActor` isolated.
- Decode, palette extraction, model inference, rendering, and export use cancellable tasks or dedicated queues.
- Model inference concurrency is bounded; running many tiles simultaneously must not cause memory spikes.
- Results carry session and operation identifiers so obsolete previews are discarded.
- Video backpressure ensures the reader does not outrun inference and writer capacity.

## Undo

Use `UndoManager` around domain operations.

- Crop, resize, upscale configuration, annotation creation, geometry, timing, style, order, and deletion are undoable.
- Drags coalesce into one operation.
- Playback, zoom, and pan are not document edits.
- Full pixel buffers are never placed in the undo stack.

## Persistence and recovery

The first release is session-oriented and exports standard media. Persist preferences only: window state, background, colour format, annotation styles, model choice, and export defaults.

Before public release, implement lightweight recovery for long edits and jobs. A public `.imagekid` project format remains deferred unless real user needs justify its maintenance cost.

## Error model

Typed service errors distinguish unsupported media, protected video, damaged data, denied access, insufficient memory, insufficient disk, unsupported model shape, model failure, codec failure, audio incompatibility, cancellation, and export failure.

Cancellation is not displayed as an error. Every failure preserves the source and current edit state.

## Dependency policy

Prefer Apple frameworks. A third-party dependency or bundled executable requires a recorded decision, compatible redistribution terms, reproducible version pinning, and attribution. The first design deliberately avoids FFmpeg, Python, PyTorch, and proprietary SDKs at runtime.