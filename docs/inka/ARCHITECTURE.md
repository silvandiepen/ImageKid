# Inka architecture

How Inka is put together: three new packages (two shared, one app-specific), two
thin app shells, and the family's shared UI. The brush engine itself is
documented separately in [BRUSH-ENGINE.md](BRUSH-ENGINE.md).

## Package graph

```
                 ImageKidCore  (Platform: PlatformImage/Color/Render)
                   ▲        ▲
        BrushKit ──┘        └── InkaKit ──► BrushKit
        (engine)                (document)
           ▲                        ▲
        BrushRender ────────────────┤       ImageKidKit (shared UI: HomeScreen,
        (Metal)                     │        FloatingToolPanel, PanelDock(+Controller),
           ▲                        │        PanelRail, CanvasBackground, Typography)
           └───────────┬───────────┘            ▲
                    Inka (macOS) / InkaiOS (iPad)┘
```

- **`BrushKit`** — shared, app-neutral brush engine (portable, CPU-tested).
  Depends only on `ImageKidCore`. See [BRUSH-ENGINE.md](BRUSH-ENGINE.md).
- **`BrushRender`** — shared Metal compositor for BrushKit dabs. Depends on
  `BrushKit`.
- **`InkaKit`** — Inka's document/workflow only (not the engine). Depends on
  `BrushKit` + `ImageKidCore`.
- **`Inka`** (macOS) / **`InkaiOS`** (iPad) — thin app shells; depend on all of
  the above plus `ImageKidKit` for the shared UI. Apps never import each other.

Rationale for the split: the engine is deliberately Inka-neutral so ImageKid can
adopt it later; keeping Metal in `BrushRender` keeps `BrushKit` CPU-testable from
the terminal; `InkaKit` holds only what is Inka's.

## The document (`InkaKit`)

`InkaDocument` is a fixed-pixel canvas, an ordered `Layer` stack (bottom→top),
an embedded brush-preset table, and a palette. It is **vector + raster hybrid**:
a `Layer.content` is one of

- `.strokes([BrushStroke])` — editable brush strokes (the vector half);
- `.raster(PNGImage)` — flat painted pixels;
- `.imported(PNGImage)` — a placed image.

`BrushStroke` (the persisted stroke — its `StrokeInput`, `brushID`, colour and
jitter `seed`) lives in **BrushKit**, not InkaKit, precisely so it is shareable.

### `.inka` workfile

`InkaWorkfile.encode/decode` — the whole document as one versioned JSON file;
raster/imported pixels ride as base64 PNG inside `PNGImage`, so a document is
self-contained (no sidecar files, local-first). Decode re-adds any built-in
brush a stroke references, so old files keep resolving as the library grows.

### Non-destructive rasterization

`InkaRasterizer.flatten(document)` composes the visible layers (honouring order,
opacity and blend mode). Stroke layers are **re-generated through the brush
engine on demand** — nothing is baked until export — so changing a brush or a
stroke's colour re-renders cleanly. It uses BrushKit's CoreGraphics
`ReferenceRenderer` so it is portable and Metal-free; the live canvas uses the
GPU path, and because both stamp the same `Dab`s they agree.

## Rendering pipeline

Two renderers, one dab list (see [BRUSH-ENGINE.md](BRUSH-ENGINE.md)):

- **Live canvas** — `InkaCanvasRenderer` (in each app shell) drives an `MTKView`.
  It keeps two textures: **committed** (everything drawn) and **live** (the
  stroke in progress, re-stamped whole each frame so within-stroke overlap never
  builds up). A `FullscreenBlitter` presents committed + live over the drawable.
  On stroke end the live texture is stamped into committed and the finished
  `BrushStroke` is handed back to the document. Committed is `.shared` storage so
  it can be read back for PNG export.
- **Export / flatten / tests** — `InkaRasterizer` / `ReferenceRenderer` (CPU).

Coordinate convention is **top-left origin** end to end (Metal shader, reference
renderer, document); an asymmetric orientation test guards it.

## Input capture

Each shell converts platform input into one `StrokeInput` (canvas pixels):

- **macOS** (`InkaCanvasView`) — an `MTKView` subclass forwards mouse/tablet
  drags; pressure from `NSEvent.pressure` (real on a graphics tablet, 1 for a
  mouse).
- **iPad** (`InkaCanvasView`, InkaiOS) — a UIKit `MTKView` subclass reads
  Apple Pencil `force`/`altitudeAngle`/`azimuthAngle` and **coalesced touches**
  (so fast strokes keep every sample); a finger draws at full pressure.

The `InkaCanvasRenderer`/`FullscreenBlitter` are duplicated across the two
shells today (both are cross-platform Metal); extracting a shared canvas module
is a small later refactor.

## Panels and UI

Inka uses the family's floating-panel system from **ImageKidKit**, the same one
ImageKid and Fekthor use — nothing bespoke:

- `HomeScreen` for the empty state.
- A rail (`PanelDockRail` + `panelRailChrome`) and dockable `FloatingToolPanel`s,
  driven by a `PanelDockModel<InkaPanel>` and the reusable **`PanelDockController`**
  (the drag/settle/place glue, newly extracted into ImageKidKit so all apps can
  share it instead of hand-rolling it).
- Panels: **Brushes** (preset grid) and **Brush** (the editor). They dock to the
  right by default in Inka.

## App state

`InkaModel` (`@MainActor ObservableObject`, one per shell) owns the document, the
live renderer, and the working `Brush`/colour. Selecting a preset replaces the
working brush; the brush editor mutates it live; committed strokes are recorded
onto the top stroke layer. Export flattens the committed canvas to PNG (macOS
save panel / iPad share sheet).

## Build & run

```bash
# Engine + document packages
cd packages/BrushKit && swift test
cd packages/BrushRender && swift test
cd packages/InkaKit && swift test

# CLIs (headless renders)
swift run --package-path packages/BrushKit brush <out-dir>
swift run --package-path packages/InkaKit inka <out-dir>

# The apps (Xcode project is generated)
npm run release:project
xcodebuild -project apps/native-macos/ImageKid.xcodeproj -scheme Inka \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
# InkaiOS: xcodegen in apps/native-ios, build the InkaiOS scheme for a simulator
```

The macOS app accepts `--open-canvas` to boot straight onto a canvas (a
debug/UI-test hook, since the home cards need a real click).
