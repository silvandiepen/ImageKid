# Inka

Inka is the ImageKid family's drawing & illustration app, and the newest of the
three flagships. Where **ImageKid** is a media utility and **Fekthor** is a
vector editor, Inka is for **expressive, pressure-driven painting** — its reason
to exist, and its sharpest edge, is a serious brush engine.

It runs on **macOS and iPad** (Apple Pencil), stays fully local (no accounts,
uploads, or cloud), and shares the family's UI and, deliberately, its brush
engine — so ImageKid can adopt real brushes later.

## Documents

- **[BRUSH-ENGINE.md](BRUSH-ENGINE.md)** — the flagship: the brush model, dab
  generation, dynamics, grain, renderers, and the `.inkbrush` format.
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — packages, the hybrid document and
  `.inka` format, the Metal pipeline, input capture, and panels.
- **[PLAN.md](PLAN.md)** — decisions, the phased roadmap, and current status.

## Status (honest)

**Feature-complete as a drawing app on macOS and iPad; launch polish (website,
brand, store) still pending.** The engine, the hybrid document, and the full
drawing/illustration workflow are in on both surfaces. Do not present the
still-PLANNED items below as done.

- **P0 Foundations** — DONE. The three packages (BrushKit, BrushRender, InkaKit),
  tested; engine output verified via the `brush`/`inka` CLIs.
- **P1 Walking skeleton** — DONE. Both shells boot, draw a pressure stroke, and
  export a PNG.
- **P2 Serious brushes** — DONE (engine + macOS editor). Response curves, tilt,
  hue jitter, procedural grain (CPU/GPU parity), square tips, 1€ smoothing; a
  brush editor with live preview and `.inkbrush` import/export; five presets.
- **P3 Hybrid layers (macOS)** — DONE. The committed canvas is rebuilt from the
  document every change (so it stays the source of truth); a Layers panel with
  add / delete / reorder / per-layer visibility + opacity and active-layer
  selection; strokes paint onto the active stroke layer.
- **P4 Illustration workflow (core, both surfaces)** — DONE. Undo/redo (⌘Z / ⌘⇧Z
  on macOS; two-/three-finger tap on iPad; 40-deep document-snapshot history),
  `.inka` document save/open (⌘S / ⌘O on macOS; Files importer/exporter on iPad)
  plus New with a size, clear-layer, PNG export through the exact CPU rasterizer.
- **Free canvas transform (both surfaces)** — DONE. The canvas is freely movable:
  pan, zoom, and **rotate** about its centre (macOS: scroll-pan, pinch-zoom,
  trackpad rotate; iPad: two-finger pan, pinch, and rotate — recognised together).
  Fit (⌘0) resets pan, zoom and rotation. Input maps through the exact inverse
  transform, so drawing/eyedropper/move stay correct on a rotated canvas.
- **Eraser (both surfaces)** — DONE. A destination-out blend in the shared
  compositor + rasterizer and an `erase` flag on `BrushStroke`; the eraser uses
  the current brush's tip, erases non-destructively, and flattens on export.
- **Colour (both surfaces)** — DONE. A Colours panel (working well, document
  palette + session recents) and an eyedropper that samples the committed canvas.
- **Selection + transform (both surfaces)** — DONE. A move tool: marquee-select
  strokes on the active layer, then **move / scale / rotate** via handles
  (non-destructive — it re-positions the vector strokes), delete; macOS adds
  arrow-key nudge (⇧ = ×10) and escape.
- **Canvas flip (both surfaces)** — DONE. Horizontal / vertical view mirror (a
  composition aid; the document is untouched); fit resets it.
- **Import image as a layer (both surfaces)** — DONE. Any image imports as a
  canvas-fit `.imported` layer, shown live on the GPU canvas and on export.
- **Layered export (both surfaces)** — DONE. Export the flattened PNG or one PNG
  per visible layer (macOS to a folder; iPad shares the files).
- **iPad parity** — DONE. The iPad app runs the same document, layers, tools and
  transform as macOS on the ImageKidKit floating panel dock, plus Procreate-style
  gestures: Pencil (or a finger) draws, two fingers pan, pinch zooms, two fingers
  rotate, two-finger tap undoes, three-finger tap redoes.
- **Website** — DONE (baseline). An Inka product page (`/inka`) and docs page
  (`/docs/inka`) in the family style, in the app registry / nav / docs index, with
  an accent colour, the Inka mascot (cut-out character render) and its app icon.
  Section marketing imagery + the native AppIcon iconsets still to drop in.
- **P5–P6 remaining** — PLANNED. See [PLAN.md](PLAN.md). Not required for a usable
  app, still open before a polished launch: wet/smudge/blur brushes, brush groups,
  custom-texture import, per-layer blend modes + masks, PSD export, colour harmony,
  the final brand icon + page imagery, and the store entry.

## What works today (macOS + iPad)

Open a canvas (or an `.inka` file), pick one of five built-in brushes (Ink Pen,
Pencil, Charcoal, Airbrush, Marker), tune it in the brush editor with a live
preview, paint with tablet/Pencil pressure on a Metal canvas, **erase**, work
across layers (add/reorder/hide, per-layer opacity), **import an image as a
layer**, freely pan/zoom/**rotate**/**flip**/fit the canvas, pick colours
(palette, recents, eyedropper), **marquee-select and move/scale/rotate/delete**
strokes, undo/redo, save and reopen the document as `.inka`, and export a
flattened **or per-layer** PNG. Both surfaces share the engine, the document, and
the floating panel dock; the iPad adds touch gestures. Strokes are stored as
editable vector `BrushStroke`s and the canvas is re-rasterized from the document
on every change, so undo, layer visibility and opacity are all non-destructive.

## Verification

```bash
cd packages/BrushKit    && swift test    # 35
cd packages/BrushRender && swift test    #  4  (skips without a GPU)
cd packages/InkaKit     && swift test    #  9
```

Plus the family regression: `npm run native:build && npm run native:test`, and
the `Inka` / `InkaiOS` targets build.

## Constraints (family policy)

Local-first: no accounts, telemetry, uploads, cloud, paid APIs, or runtime
downloads (brush/texture packs install locally). Canvas geometry stays in canvas
pixel space; packages are reusable; apps never import apps. See the repo
`AGENTS.md`.
