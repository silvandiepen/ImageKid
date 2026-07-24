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

**Usable on macOS, not yet launch-ready.** The engine, the hybrid document, and a
working macOS drawing app are in; the iPad shell and launch polish are not. Do not
present the still-PLANNED items below as done.

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
- **P4 Illustration workflow (macOS, core)** — DONE. Undo/redo (⌘Z / ⌘⇧Z, 40-deep
  document-snapshot history), `.inka` document save/open (⌘S / ⌘O) plus New with a
  size, canvas zoom / pan / fit (pinch, scroll, ⌘0), clear-layer, PNG export
  through the exact CPU rasterizer.
- **P5–P6 Brush breadth, iPad workflow, launch** — PLANNED. See [PLAN.md](PLAN.md).
  Still missing before any release: selections/transform, canvas rotate/flip,
  wet/smudge brushes and brush groups, layered/PSD export, and the iPad panel dock
  + gestures (the iPad shell is still the P1 walking skeleton).

## What works today (macOS)

Open a canvas (or an `.inka` file), pick one of five built-in brushes (Ink Pen,
Pencil, Charcoal, Airbrush, Marker), tune it in the brush editor with a live
preview, paint with tablet/Pencil pressure on a Metal canvas, work across layers
(add/reorder/hide, per-layer opacity), zoom/pan/fit the canvas, undo/redo, save
and reopen the document as `.inka`, and export a flat PNG. Strokes are stored as
editable vector `BrushStroke`s and the canvas is re-rasterized from the document
on every change, so undo, layer visibility and opacity are all non-destructive.

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
