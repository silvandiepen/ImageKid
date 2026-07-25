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

**Usable on macOS and iPad, not yet launch-ready.** The engine, the hybrid
document, and a working drawing app on both surfaces are in; the deeper
illustration workflow (selections/transform) and launch polish (website, brand,
store) are not. Do not present the still-PLANNED items below as done.

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
- **P4 Illustration workflow (core)** — DONE. Undo/redo (⌘Z / ⌘⇧Z on macOS;
  two-/three-finger tap on iPad; 40-deep document-snapshot history), `.inka`
  document save/open (⌘S / ⌘O on macOS; Files importer/exporter on iPad) plus New
  with a size, canvas zoom / pan / fit, clear-layer, PNG export through the exact
  CPU rasterizer.
- **P4 Colour + selection (macOS)** — DONE. A Colours panel (working well,
  eyedropper, document palette + session recents), an eyedropper that samples the
  committed canvas, and a **move tool**: marquee-select strokes on the active
  layer and drag them (non-destructive — it re-positions the vector strokes),
  arrow-key nudge (⇧ = ×10), delete, escape to deselect.
- **P6a iPad parity** — DONE. The iPad app now runs the same hybrid document,
  layers, undo/redo, save/open and canvas nav as macOS, using the ImageKidKit
  floating panel dock (Brushes / Brush / Layers) — and the Procreate-style
  gestures: Pencil (or a finger) draws, two fingers pan, pinch zooms, two-finger
  tap undoes, three-finger tap redoes.
- **P5–P6 Brush breadth, launch** — PLANNED. See [PLAN.md](PLAN.md). Still missing
  before any release: selection scale/rotate (only marquee-move exists) and colour
  tools on iPad, canvas rotate/flip, wet/smudge brushes and brush groups,
  layered/PSD export, pinch-rotate, and the website/brand/store work.

## What works today (macOS + iPad)

Open a canvas (or an `.inka` file), pick one of five built-in brushes (Ink Pen,
Pencil, Charcoal, Airbrush, Marker), tune it in the brush editor with a live
preview, paint with tablet/Pencil pressure on a Metal canvas, work across layers
(add/reorder/hide, per-layer opacity), zoom/pan/fit the canvas, undo/redo, save
and reopen the document as `.inka`, and export a PNG. Both surfaces share the
engine, the document, and the floating panel dock; the iPad adds touch navigation
gestures. Strokes are stored as editable vector `BrushStroke`s and the canvas is
re-rasterized from the document on every change, so undo, layer visibility and
opacity are all non-destructive.

## Verification

```bash
cd packages/BrushKit    && swift test    # 35
cd packages/BrushRender && swift test    #  4  (skips without a GPU)
cd packages/InkaKit     && swift test    #  7
```

Plus the family regression: `npm run native:build && npm run native:test`, and
the `Inka` / `InkaiOS` targets build.

## Constraints (family policy)

Local-first: no accounts, telemetry, uploads, cloud, paid APIs, or runtime
downloads (brush/texture packs install locally). Canvas geometry stays in canvas
pixel space; packages are reusable; apps never import apps. See the repo
`AGENTS.md`.
