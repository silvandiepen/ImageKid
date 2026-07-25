# Inka — drawing & illustration app

Decision (2026-07-24, Sil): Inka is the family's **third flagship** — a
drawing/illustration app whose defining strength is a **serious brush engine**.
It complements, never duplicates, Fekthor's vector work: Fekthor is precise
vectors, Inka is expressive pixels. The brush engine is built as a **shared
family package** so ImageKid can later adopt it.

## Shape

- **Both surfaces**: macOS (`Inka`) and iPad (`InkaiOS`), one shared engine,
  two thin app shells. Apple Pencil on iPad; Wacom/tablet + trackpad on Mac.
- **Metal GPU** live canvas — real-time stamp-based dabs, high-res, 120 Hz.
  Only the live compositor is Metal; the model/engine stay portable & tested.
- **Vector + raster hybrid** document — brush strokes are stored as editable
  `BrushStroke` values (spine + per-vertex dynamics + brush id) that
  re-rasterize non-destructively; flat raster and imported-image layers too.

## Packages (shipped in P0)

| Package | Role | Depends on |
| --- | --- | --- |
| `BrushKit` | SHARED, app-neutral engine: `Brush` (+`.inkbrush` codec), `StrokeInput` (+smoothing/velocity), `BrushEngine` (deterministic dab generation), `BrushStroke`, a CoreGraphics `ReferenceRenderer`, a `brush` CLI | `ImageKidCore` |
| `BrushRender` | SHARED Metal compositor: stamps `Dab`s into a target texture (premultiplied over), offscreen render for tests. Shader compiled at runtime from source (SwiftPM CLI does not build `.metal`) | `BrushKit` |
| `InkaKit` | Inka-specific: `InkaDocument` (hybrid `Layer`), `.inka` codec, `InkaRasterizer` (non-destructive flatten via `ReferenceRenderer`), an `inka` CLI | `BrushKit`, `ImageKidCore` |

Coordinate convention: **top-left origin** everywhere (Metal shader, reference
renderer, document). An asymmetric orientation test guards it.

Determinism: `BrushEngine` jitter comes from a seeded `SplitMix64`, so the same
stroke + brush + seed always yields the same dabs — tests and non-destructive
re-rasterization both rely on it. No `Math.random`.

## App shells (P1 walking skeleton — shipped)

- `apps/native-macos/Sources/Inka` — boots to the shared `HomeScreen`, opens a
  Metal `InkaCanvasView` (MTKView + `InkaCanvasRenderer`: committed + live
  textures, re-stamps the live stroke each frame, commits on mouse-up and
  records a `BrushStroke`), 4 built-in brushes, colour/size, PNG export. Mouse
  and tablet pressure via `NSEvent.pressure`.
- `apps/native-ios/Sources/InkaiOS` — the same, with UIKit touch capture
  (Apple Pencil force/altitude/azimuth + coalesced touches). Boots on the iPad
  simulator to the shared home.
- The `InkaCanvasRenderer`/`FullscreenBlitter` are duplicated across the two
  shells for now (both are cross-platform Metal); extracting a shared canvas
  module is a P1.5 refactor once both are proven.

## Roadmap (see docs/fekthor/EDITOR-PLAN.md for the family's phase style)

- **P0 Foundations** — DONE: the three packages above, tested; engine output
  confirmed via the `brush`/`inka` CLIs.
- **P1 Walking skeleton** — DONE: both shells boot, draw a pressure stroke, and
  export. (Live-draw GUI is not automatable in the sandbox; engine, compositor
  and rasterizer are unit-tested, output visually confirmed via CLI.)
- **P2 Serious brushes** — DONE (engine + editor): response curves
  (`ResponseCurve`) on pressure/velocity; tilt→size and tilt→angle; hue jitter;
  procedural **grain** (`GrainNoise`, per-pixel tooth in BOTH the CPU reference
  renderer and the Metal shader, from one shared hash so they agree); square
  tips; **1€ smoothing** (`OneEuroFilter`, the engine's live path). A **brush
  editor** in Inka (macOS) with a live preview and `.inkbrush` save/load, and
  two new grained presets (Pencil, Charcoal). Prediction (predicted touches)
  deferred to P4 live-capture. Grain washes out under a fully opaque flow-1
  brush (correct — a solid marker covers the tooth); it reads on low-flow media.
  Inka's macOS UI uses the family's **floating-panel system from ImageKidKit**
  (rail + dockable Brushes/Brush panels), not a bespoke sidebar. The
  drag/settle/place glue that ImageKid and Fekthor each hand-rolled is now a
  reusable `PanelDockController` in ImageKidKit; Inka uses it. (ImageKid and
  Fekthor keep their own copies for now — they can migrate onto the controller
  later; not done here to avoid destabilising them.) The iPad shell keeps its
  simple toolbar for now; adopting the panel dock there is P6.
- **P3 Hybrid layers** — DONE (macOS): non-destructive vector-stroke layers. The
  renderer rebuilds its committed texture from the document on every change, so
  the document is the source of truth; a **Layers panel** (ImageKidKit floating
  panel) with add / delete / reorder, per-layer visibility + opacity, and
  active-layer selection; strokes land on the active stroke layer (a new stroke
  layer is spun up if the active one can't take strokes). Raster + imported layers
  round-trip in `InkaDocument` and rasterize on export, but the app only *creates*
  stroke layers so far. Per-layer masks/blend modes beyond opacity are P5.
- **P4 Illustration workflow** — DONE (core): **undo/redo** (⌘Z / ⌘⇧Z; two-/
  three-finger tap on iPad; 40-deep document-snapshot history), **`.inka`
  save/open** + New with a size, **canvas nav** (pinch-zoom, scroll-pan, ⌘0 fit),
  clear-layer, PNG export via the exact CPU rasterizer. **Colour (macOS)**: a
  Colours panel with the working well, a document palette + session recents, and
  an **eyedropper** that samples the committed canvas. **Selection (macOS)**: a
  **move tool** — marquee-select strokes on the active layer and drag them (it
  re-positions the vector strokes, non-destructively), with arrow-key nudge (⇧ =
  ×10), delete and escape. Still open: selection scale/rotate, colour tools on
  iPad, canvas rotate/flip, colour harmony, reference layer.
- **P5 Brush breadth + export** — wet/smudge/blur, brush groups, custom brush
  import, perf passes; layered export.
- **P6 Polish & launch** — iPad workflow **DONE**: the iPad app has full macOS
  parity (hybrid document, layers, undo/redo, `.inka` save/open, canvas nav) on the
  ImageKidKit floating panel dock, plus Procreate-style gestures — Pencil/finger
  draws, two-finger pan, pinch-zoom, two-finger tap undo, three-finger tap redo.
  Still open: pinch-rotate, **website Inka page + brand assets** (deferred to avoid
  broken image refs), release-boundary entry.
- **P7 (opt-in) ImageKid adoption** — route ImageKid's freehand through
  `BrushKit`/`BrushRender`, retiring `MaskPainter.paintStroke` / the iOS
  `Brush.swift` presets.

## Constraints
Local-first: no accounts, telemetry, uploads, cloud, paid APIs, runtime
downloads (brush/texture packs install locally). Canvas geometry stays in canvas
pixel space; the app maps its view coordinates. Packages reusable; apps never
import apps.

## Verification
- `swift test` in `packages/BrushKit` (35), `packages/BrushRender` (4),
  `packages/InkaKit` (7).
- `swift run brush <dir>` / `swift run inka <dir>` render sample strokes/PNGs.
- `npm run release:project` then build `Inka`; `xcodegen` + build `InkaiOS`
  (iphonesimulator). Both boot to the shared home.
