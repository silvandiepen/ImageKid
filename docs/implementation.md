# Implementation status

## Build foundation

The native app is a Swift Package Manager executable in `apps/native-macos` targeting macOS 14. Open `apps/native-macos/Package.swift` in Xcode 16 and run the `ImageKid` scheme on My Mac, or run `swift build`, `swift test`, and `swift run ImageKid` from `apps/native-macos`. Root helpers are available as `npm run native:build`, `npm run native:test`, and `npm run native:run`.

The package form keeps the initial repository small, reviewable, and directly testable. Distribution work will require a signed application target, bundle metadata, assets, sandbox entitlements, archive configuration, and notarisation or App Store configuration.

## Implemented

- SwiftUI application lifecycle and native command menus.
- SwiftUI empty drop state with app-controlled light/dark appearance, native drop target, Open action, and asset slots for character and plant artwork.
- macOS Settings scene with System integration preferences, Appearance, canvas background (Light/Dark/Transparent checkerboard/Custom colour plus an opacity wash — the shared `ImageKidKit.CanvasBackground` model and controls, identical to Fekthor's), background-removal engine/model install state, upscale engine/runtime install state, and secure OpenAI API key storage.
- Open panel, drag and drop, URL paste, and image paste.
- Images opened from Finder ("Open With", double-click) or dropped on the Dock icon open in the workspace: the bundle declares `public.image` as an Editor document type at Alternate rank, so Preview stays the system default while ImageKid becomes a first-class handler.
- Image loading with `NSImage`.
- Video loading and playback with AVFoundation and AVKit.
- Image fit, mouse pan, two-finger trackpad pan, pinch zoom, and view reset.
- Correct top-to-bottom press-and-drag image colour sampling with a large live swatch.
- Persistent colour panel with multi-selection, removal, colour adjustment, expanded HEX/RGB/RGBA/HSL/SwiftUI values, copy formats, and file export.
- Crop overlay with corner and edge handles, rule-of-thirds guides, ratio choices, editable pixel dimensions, reset, cancel, Escape cancellation, and apply.
- Applied crop immediately reframes the working canvas and remains the basis for viewing, picking, annotations, and further crops.
- Resize tool with draggable output frame, exact size fields, percentage presets, aspect lock, and explicit apply/cancel.
- Editable rectangles, ellipses, lines, arrows, and freehand annotations.
- Reliable freehand input from mouse-down through mouse-up, including short and fast strokes.
- Drawing settings for mode, stroke colour, fill, thickness, and opacity.
- Text annotations that remain editable, movable, resizable, deletable via Delete/Backspace, and configurable with font, weight, line height, alignment, and colour.
- Contextual text settings for content, font family, size, weight, alignment, and colour.
- On-device image background removal using Apple Vision foreground instance masks, with reversible restore and Keep/Remove refinement brushes.
- A one-time Best Quality offer: the first background removal or enlargement run without the optional on-device model asks whether to use it. Accepting switches that feature's engine over, starts the download and opens Settings on its progress; declining is remembered per feature and never asked again. Either answer still performs the action immediately with the installed engine, and a selected-but-missing Best Quality model falls back to the built-in engine instead of failing.
- Draggable vertical contextual panels with a dark translucent surface and large corner radius.
- Image export sheet with PNG, JPEG, HEIC, TIFF, BMP, and GIF, quality, scale, upscaling engine, transparency background, and Finder reveal controls.
- Full-resolution image export rendered from source media and edit state.
- Optional Best Quality image upscaling through an app-managed local Real-ESRGAN ncnn Vulkan runtime. The runtime is downloaded from Settings, stored in Application Support, and executed on-device during exports that enlarge the cropped source.
- Prompted image editing for the current rendered image through a provider-neutral app service. OpenAI is the first provider and uses the user-supplied API key from Keychain. The result replaces the current workspace image and is marked dirty.
- Managed Quick Action workflows for future Finder Services or Quick Actions. Settings includes a dedicated Actions tab where default and custom actions are shown, default actions can be enabled/disabled but not deleted, and custom actions can be created, renamed, deleted, reset, and composed from ordered steps such as Remove Background, Upscale 2x/4x, and fitting onto a transparent canvas size. `--quick-action <action-id> <images…>` opens a minimal progress window and writes sibling output files without overwriting the source. The default-on `showInFinderContextMenus` setting is in place for the later OS registration layer.
- Initial macOS companion targets exist for `ImageKid Upscale` and `ImageKid Cutout`. They share a focused batch queue, support drag/drop and Open panel input, process images one at a time on device through `ImageKidInference`, and write generated files to a sibling output folder or chosen destination. The upscaler supports Standard Core Image and Best Quality Core ML when the shared Real-ESRGAN model is installed. The cutout app supports Built-in Apple Vision and Best Quality Core ML when the shared BiRefNet model is installed. ImageKid and the companion apps use the same App Group model cache when signed with `group.com.hakobs.imagekid`, with a development fallback to Application Support.
- Geometry, crop-coordinate, freehand-input, and colour-coordinate mapping unit tests.
- macOS CI build and test workflow.

## Fekthor (vector editor)

Fekthor is the monorepo's second flagship: a workspace-first native macOS
vector editor (`com.hakobs.fekthor`, `apps/native-macos/Sources/FekthorTrace`)
with its engine in `packages/FekthorKit` (SwiftPM, deterministic, 393 unit
tests, its own `fekthor` CLI target and fixture-based eval harness). A
folder-backed workspace presents icons in a searchable gallery; documents
carry named styles, design tokens, and swatches, including file-local ones;
and export runs through named non-destructive profiles with container and
partial support. Editing covers pen, shape, transform, and corner tools,
gradients, and node editing (anchors, Bezier handles, undo). Raster tracing is
a built-in feature rather than a separate app: Auto/Shapes/Strokes/Gradient
modes with mode-aware quality scoring, Split/Overlay/Wipe comparison,
Auto-tune settings search, opt-in variable-width stroke envelopes, and
optional on-device Real-ESRGAN enhancement (explicit-action model download,
same source as the companions). Rasters pasted or dropped onto an editor
canvas stay rasters: they become `<image>` nodes with their pixels embedded
as base64 PNG (documents stay one self-contained SVG), select, move, scale
and rotate like any node, and right-click ▸ Vectorize traces one in place —
Save swaps the traced geometry in at the image's exact frame as a single
undo step. The floating panel system lives in
`packages/ImageKidKit` (54 unit tests) and is shared across the family.
Fekthor depends on FekthorKit, ImageKidKit, and ImageKidInference; like all
apps here it never imports from another app. Thor remains the app's
mascot/branding.

## Inka (drawing & illustration)

Inka is the family's third flagship: a macOS + iPad drawing/illustration app
built around a serious brush engine (`com.hakobs.inka`; `apps/native-macos/
Sources/Inka` and `apps/native-ios/Sources/InkaiOS`). The brush engine is a
**shared family package**, not locked in Inka: `BrushKit` holds the app-neutral,
CoreGraphics-testable core — `Brush` presets (+`.inkbrush` codec), captured
`StrokeInput` with smoothing, deterministic stamp-based `BrushEngine` dab
generation, `BrushStroke`, a reference renderer and a `brush` CLI (19 unit
tests) — and `BrushRender` is the shared Metal compositor that stamps those dabs
into a texture (3 unit tests, runtime-compiled shader). `InkaKit` (7 unit tests,
`inka` CLI) is Inka-specific: the vector+raster hybrid `InkaDocument` (a layer is
editable brush strokes, flat raster, or an imported image), the `.inka` workfile
codec, and non-destructive flatten (stroke layers re-rasterize on demand, so
changing a brush or colour re-renders cleanly). Both app shells (P1 walking
skeleton) boot to the shared `HomeScreen`, open a Metal canvas, paint a
pressure-varying stroke (NSEvent tablet pressure on Mac; Apple Pencil force/tilt
on iPad), and export a PNG. The engine (P2 done) carries real depth: response
curves on pressure/velocity, tilt→size/angle, hue jitter, procedural paper
**grain** applied per-pixel identically in the CPU reference renderer and the
Metal shader, square tips, and a 1€ live-smoothing filter — five built-in
brushes (Ink Pen, Pencil, Charcoal, Airbrush, Marker) show the range, and Inka's
macOS **brush editor** exposes every parameter with a live preview and
`.inkbrush` save/load. Inka depends on BrushKit, BrushRender, InkaKit,
ImageKidKit and ImageKidCore; like every app here it never imports another app.
Inka is a feature-complete drawing app on **both macOS and iPad** — hybrid
vector-stroke layers (rebuilt from the document each change), a layers panel,
undo/redo, `.inka` save/open, a free canvas transform (pan/zoom/**rotate**/**flip**
/fit), an **eraser**, colour tools (palette, recents, eyedropper), a **move tool
with move/scale/rotate**, **image import** as a layer, and **flattened + per-layer
export** — all on the shared ImageKidKit floating panel dock; the iPad adds
Procreate-style touch gestures. Launch polish still pending: wet/smudge brushes,
per-layer blend modes/masks, PSD, and the website/brand/store. See `docs/inka/` —
[README](inka/README.md), [BRUSH-ENGINE](inka/BRUSH-ENGINE.md),
[ARCHITECTURE](inka/ARCHITECTURE.md), [PLAN](inka/PLAN.md).

## Incomplete or provisional

- The live colour picker currently presents a colour swatch rather than a pixel-grid magnifier.
- Palette extraction from dominant image colours remains.
- Blur, pixelation, annotation ordering, duplication, and rotation remain.
- Text editing is performed through the contextual panel rather than direct inline canvas typing.
- Undo, redo, close protection, recovery, and document lifecycle remain.
- Video currently provides viewing and playback only. Video colour picking, crop, resize, annotations, and export remain a separate major technical slice.
- Prompted edits currently apply to the whole rendered image. Region masks, outpainting canvas expansion, provider selection UI, and alternative providers remain.
- Metadata preservation and advanced colour-profile controls remain. Current exports intentionally render a fresh file without source metadata.
- Sculptor runs end to end locally — import, generate, inspect, export GLB — across `tools/sculptor-engine` (worker), `packages/ImageKidSculptorKit` (protocol, worker bridge, session, model download) and `apps/native-macos/Sources/ImageKidSculptor` (app). TripoSR replaced SPAR3D as the V1 engine because SPAR3D's weights are gated; `engines/spar3d.py` exists but has never been executed. Reconstruction quality is usable for background assets and blurs intricate subjects. The Sculptor target is **not sandboxed**: it launches a developer-provided Python interpreter, and a sandboxed process may only execute binaries inside its own bundle. Packaging that runtime, restoring the sandbox, and replacing the protocol's stage weights with measured timings all remain. See `docs/sculptor.md` "Phase 0 findings".
- The Swift package does not yet define production signing, sandboxing, or distribution settings.
- Finder context menu registration remains unimplemented until the native target has signed app bundle metadata and either Finder Services or a Finder Sync/Action extension.

## Deferred

Video processing, document lifecycle, and undo/redo remain deferred. Best Quality upscaling and Best Quality background removal are opt-in local runtime installs. Prompted image edits are opt-in provider calls rather than local processing.
