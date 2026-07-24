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

Backlog status 2026-07-23: items 1–4 SHIPPED (swatches/align/history/
point-snap; layers/named-styles/classes; transform+distort/guide;
linear+radial gradient editing). Multipoint/mesh gradients deliberately
parked (Sil) — if ever: multipoint model in the workfile, export-time
flattening (blurred-blob default / raster / radial-stack). Panel system
gained shared magnetic stacking + minimize-to-chip (ImageKidKit, both
apps + first iPad surface).

## Placed images & in-place Vectorize (2026-07-24, Sil)

Trace stopped being only an entry path: a raster dropped or pasted onto an
editor canvas STAYS a raster. Document Model v2 gained
`GraphicNode.image(ImageNode)` — an `<image>` rect with the pixels embedded
as a base64 PNG data URI, so the document is still one self-contained SVG
that round-trips through the reader/writer untouched. Placed images select,
move, scale and rotate with everything else (translate/scale fold into the
rect; rotation/mirroring ride a matrix, since a rect cannot express them),
render through one shared engine path (canvas, thumbnails, PNG/PDF export),
and cap at 2048px on the longest side.

Right-click ▸ Vectorize hands that image's pixels to the trace flow while the
editor session stays loaded underneath; Save maps the traced document into
the image's own frame — geometry, stroke widths and gradient coordinates all
BAKED (`TracePlacement`) — and swaps it in at the image's z-position as one
"Vectorize" undo step. Cancel leaves the picture untouched.

Open: drops land centred on the artboard rather than at the drop point;
placed images are not yet a source for Free Distort or the boolean ops.

Engine follow-ups from the gradient wave: SVGReader should retype
modelled gradient defs (app-side normalizer in EditorGradients.swift
retires then); ThumbnailRenderer still flattens gradients to the first
stop; GradientStop lacks stop-opacity.

## Animations (SHIPPED 2026-07-24 — see ANIMATIONS.md)

CSS animations authored in Fekthor, baked into source SVGs as a generated
`<style id="fekthor-animations">` block (idempotent RawNode; zero writer
changes). Defs in the workfile (`animations`), resolved copies + bindings
(the icon's scene) in FileMeta — undo-covered for free. Marker-class
bindings (`fk-anim-*`, root class = whole icon), per-binding triggers
(continuous/hover/focus/active/parent-class/manual), consumer contract
(`.animate*` utilities + `--icon-animate-*` custom properties, `:where()`
zero-specificity, reduced-motion, static-first via animation-name gating).
Editor: engine interpolator (UnitBezier/steps, golden-tested) drives canvas
playback; Animation palette; bottom timeline drawer (tracks, 1%-grid
keyframe drags, easing popover + bezier pad, delay/duration span drags,
record mode with workspace-def forking); Workspace ▸ Animations… library
sheet with count-confirmed propagation. Export: `strip-animations`/
`bake-animations` actions, enabled-toggle default policy, meta stripped
after actions, flatten preserves bound groups. Verified animating in
Chrome (spin/hover-draw/gated).

## Editor polish round (2026-07-24, Sil)

- **Select All (⌘A)** picks every visible object — hidden and locked layers
  stay out, hidden groups skip their subtree, `defs`/metadata are not
  objects. No document mutation, so no undo step.
- **Panel rail**: smaller chips (32pt, glyph and radius scale with them —
  `MinimizedPanelChip(size:)`), instant hover tips PLUS system tooltips, and
  a height-driven split (`PanelRailLayout` in ImageKidKit, unit-tested):
  what does not fit moves behind a ⋯ button that takes the last slot. Rail
  membership is the rail ORDER — drag a button onto ⋯ to demote it, drag one
  out of the ⋯ popover (or its "Move to Rail" menu item) to promote it —
  and the shipped default order is ranked by everyday use, so the tail that
  lands in the overflow is the stuff you rarely open.
- **Colour dots** are one component (`SwatchDot`) across the Swatches
  palette, the swatch picker and the Fill/Stroke wells. The style palettes
  dropped their hex field: the dot is the control; typing an exact value
  lives in the picker's Custom… and the rail wells' editor.
- **Pen cursor** hotspot moved to the nib at the TOP of the glyph (it was
  clicking a glyph-height below where the tip is drawn).

## Open items

- Undo architecture decision (snapshots vs commands) due at P3 exit.
- Trace: transparent-PNG pipeline fix in flight (primitive-tolerance 8x bug
  found; face-boundary corruption upstream under investigation).
- Build-out 2026-07-22: P1–P3 engines + editor-core features being built in
  parallel (workspace scan/meta/file-ops, export actions incl. outlineStrokes,
  containers compose/matrix, colour-slot tokens, insert-anchor/z-order/group).
