# Fekthor: vector editor plan

Decision (2026-07-22, Sil): Fekthor is a **vector editing app** — "the basics
of Illustrator, but better" — and its sharpest edge is **icon-set work**.
Tracing is ONE feature (big, flagship-grade), not the product. The app is
named **Fekthor** (com.hakobs.fekthor); "Fekthor Trace" is retired as a name,
Trace lives on as the feature.

## The driving use case: icon sets

Sil's real Illustrator pain, verbatim distilled:

- A full icon set across multiple categories, with **no artboard limits**.
- **Layout is the app's job**: the gallery/grid of icons arranges itself;
  the user never hand-positions artboards.
- **Folder-backed**: the icons/artboards live in a folder on disk (categories
  = subfolders); the app manages the folder, not the user.
- **Non-destructive export modes with actions**: icons are authored as
  strokes/lines, but exports need flattened/outlined paths. Outlining must
  happen AT EXPORT, never destroying the editable source.
- Proper artboard/icon **naming** and metadata.

## Product shape

Two faces, one app:

1. **Workspace** — open a folder / .fekthor: a gallery of documents grouped
   by category (subfolders), auto-laid-out, searchable, renameable. A
   workspace is any organized collection: an icon library, a series of
   logos, a font in progress (glyph per artboard). Every entry is one small
   vector document with one artboard.
2. **Editor** — open an entry (or a blank artboard): the full vector editor
   (everything built 2026-07-22: selection, anchors, handles, break/merge/
   remove, colour, swatches, undo — plus the tool phases below).

Trace is an entry path into either: Edit ▸ Trace Image…, dropping a raster
into the editor, or dropping one into the workspace (traces into a new entry).

## Styles & tokens (workspace standards)

InDesign has paragraph/character styles; Fekthor does it for every vector
property. Defined in the workfile, referenced everywhere:

- Token kinds (v1): colour, stroke style {width, colour, cap, join, dash},
  corner radius, artboard/grid sizes. More later.
- **SVGs stay clean**: files always contain RESOLVED values. The binding
  (path X uses stroke.primary) lives in the workfile, keyed by standard SVG
  path `id`s — legitimate SVG, no metadata pollution.
- **Editing a token re-resolves and rewrites every bound SVG on disk** —
  change the set's stroke width once, every icon updates.
- Drawing/editing picks up the ACTIVE style; a Styles panel manages tokens.
- Radius tokens bind to parametric geometry first (rect primitives already
  carry cornerRadius); corner-rounding of arbitrary paths is a later op.
- Export profiles may reference tokens (e.g. recolour maps token → value).

## Why "better" is credible

- Native and instant; live-vector canvas; no subscription; fully local.
- Icon workflow is FIRST-class: folders, categories, batch export pipelines —
  Illustrator needs plugins and discipline for this; Fekthor makes it the
  default shape of the app.
- Non-destructive export actions, powered by engine machinery that already
  exists (stroke outlining/envelopes, flatten, simplify, recolour).
- Tracing produces semantic vectors (typed lines/arcs/cubics, real stroke
  widths) that the editor can genuinely edit.

## Native format decision (RESOLVED 2026-07-22, Sil)

Hybrid: plain SVG for geometry, a `.fekthor` workfile for everything else.

- **.svg** — the icons, always clean. Geometry source of truth. Opening any
  SVG and saving overwrites it plain; Fekthor NEVER injects metadata into
  SVGs, so folders stay git-diffable and directly usable in web projects.
- **.fekthor** — the workfile (Codable JSON): referenced icons folder
  (relative path), category/gallery config, artboard names/sizes/grid,
  export profiles + actions, palette/swatches, trace presets. May ALSO embed
  artboards + geometry directly → a self-contained multi-artboard document
  (poster, logo sheet) works as one file with no folder.
- Open flows: `.fekthor` → full project; a folder → find-or-create
  `set.fekthor` at its root; a lone `.svg` → standalone edit, save in place.

Typical layout:

    icons/
      set.fekthor        # workfile: profiles, categories, artboard meta
      arrows/…svg  ui/…svg
      dist/              # export profiles write here; never hand-edited

## Export profiles (the non-destructive pipeline)

Per-library named profiles, each a list of actions applied to a COPY at
export time:

    profile "web-outlined":
      actions: [outlineStrokes, flatten, fitArtboard(24), snapToPixels?]
      format: svg
      out: dist/outlined/{category}/{name}.svg

- Actions (initial set): outlineStrokes (constant-width expand — engine work,
  sibling of the existing variable-width EnvelopeBuilder), flatten/merge
  overlapping fills, resize/fit, recolour (map palette → tokens/currentColor),
  strip metadata, PNG raster at N sizes.
- Batch: run a profile over the whole library or a category; deterministic
  output naming from templates.

## Document Model v2 (enabling change, unchanged from before)

    Document → Artboard(s) → Layers → Nodes
    Node = Group(children, transform) | PathObject(geometry, style, transform)
    Style = { fill: Paint?, stroke: { paint, width, cap, join, dash }? }

Fixes the core flaw (elements are currently fill XOR stroke), keeps typed
geometry, adds transforms/groups/ids. Trace output maps losslessly.

## Phases

- **P0 Foundation** — DONE 2026-07-22: Model v2 + bridge, full SVG
  read/write (917/917 open-icon corpus round-trips, normalize-on-first-save,
  idempotent writer), Editing2, Workfile v1, editor session/canvas, file
  menu; P0 gate green (open real icon → move anchor → save → reopens intact,
  second save byte-identical).
- **P1 Workspace**: folder-backed collections, category grid, naming,
  search, move between categories, drop-PNG-to-trace into the workspace.
- **P2 Export profiles**: outlineStrokes engine op + profile storage +
  batch runner + naming templates.
- **P3 Styles & tokens**: token store in the workfile, id-keyed bindings,
  propagation rewrites, Styles panel, draw-with-style.
- **P4 Editor core**: move/scale/rotate handles, group/z-order, full
  fill+stroke style panel (token-aware), shape tools.
- **P5 Pen & path ops**: pen tool, join/simplify, booleans.
- **P6 Interchange & polish**: SVG import of foreign files, PNG/PDF export,
  guides/snapping, align/distribute.

P1–P3 deliver the workspace pain-killers early; deep editing rides on the
already-working editing toolkit meanwhile.

Discipline: per-phase in-depth plan docs with acceptance criteria before
implementation; every step a verified conventional commit.

## Illustrator-parity backlog (Sil, 2026-07-23)

Confirmed must-haves, in build order. Shared UI shells graduate into
ImageKidKit (FloatingToolPanel already shared) so Fekthor and ImageKid
stay visually identical.

1. Swatches palette (workspace `swatches` in workfile; click=fill,
   ⌥=stroke, promote-to-token) · Align palette (engine shipped) ·
   History palette (label undo snapshots, jump-back; mirror ImageKid's
   HistoryPanel) · snap-to-points (anchor/bounds magnets + tick feedback).
2. Layers palette (document tree: reorder/hide(display:none)/lock) ·
   Named styles (style = SVG class, values inline; workfile
   `namedStyles`; propagation rewrites only bound files — engine landing).
3. Transform palette (numeric skew/shear/scale/rotate baked into
   geometry via TransformOps — never a transform attribute) · workspace
   guide icon (role-style underlay behind every icon, toggleable).
4. Gradient editing (Fill palette mode + on-canvas axis/stop handles —
   "better and easier than Illustrator") · live corners on paths.

## Open items

- Undo architecture decision (snapshots vs commands) due at P3 exit.
- Trace: transparent-PNG pipeline fix in flight (primitive-tolerance 8x bug
  found; face-boundary corruption upstream under investigation).
- Build-out 2026-07-22: P1–P3 engines + editor-core features being built in
  parallel (workspace scan/meta/file-ops, export actions incl. outlineStrokes,
  containers compose/matrix, colour-slot tokens, insert-anchor/z-order/group).
