# Fekthor Animations: CSS animations baked into SVG icons

Decision (2026-07-24, Sil): Fekthor authors **CSS animations for icons** —
baked into the source SVGs as a generated `<style>` block so icons animate
when inlined in HTML, while remaining pixel-perfect static icons everywhere
else. Reusable animation assets live in the workspace like tokens/named
styles; v1 ships a **full timeline editor** (tracks, draggable keyframes,
easing editor, scrubber, in-canvas playback). No other vector editor does
this; it is a flagship differentiator for icon-set work.

## Principles

- **Static-first.** An icon whose animations are not triggered renders
  pixel-identical to its static export. Achieved structurally: triggers gate
  `animation-name`, so an untriggered element carries no animation at all.
- **SVGs stay clean-ish.** The generated block is legitimate SVG
  (`<style id="fekthor-animations">`), clearly delimited, regenerated on
  every save (never hand-edited, never parsed back). Everything else about
  the clean-SVG contract holds: geometry inline, no foreign metadata beyond
  the existing `fekthor-meta` block.
- **Workfile is master, SVG is self-contained.** Definitions live in the
  workfile (`Workfile.animations`); the defs an icon uses are copied
  (resolved) into that icon's `fekthor-meta` on save, so a lone SVG opened
  without a workspace still shows and edits its animations. Editing a
  workspace def propagates: FileMeta copies and style blocks are rewritten
  across bound files (NamedStyles propagation pattern).
- **Consumers always win.** Every selector is wrapped in `:where()` (zero
  specificity); all timing goes through CSS custom properties with baked
  fallbacks; `prefers-reduced-motion` is respected by default.

## The consumer contract (public API of exported icons)

Utility classes, placed on the `<svg>` or any ancestor (all optional):

| class | effect |
|---|---|
| `.animate` | force-play every animation in the icon |
| `.animate-once` | play once, hold the end state (`fill-mode: forwards`) |
| `.animate-infinite` | loop forever |
| `.animate-hover` | play while the tagged element is hovered |
| `.animate-on-parent-hover` | play while an ancestor is hovered |
| `.animate-focus` | play while focus is inside (`:focus-within`) |
| `.animate-active` | play while active |

Custom properties (two-level fallback; `<name>` = animation name):

    --icon-animate-duration        --icon-animate-<name>-duration
    --icon-animate-timing          --icon-animate-<name>-timing
    --icon-animate-delay           --icon-animate-<name>-delay
    --icon-animate-iteration       --icon-animate-<name>-iteration

Example emitted longhand:

    animation-duration: var(--icon-animate-spin-duration,
                        var(--icon-animate-duration, .8s));

Context behavior: inlined in HTML → full contract. `<img>`/standalone →
continuous animations still run; interaction triggers are dead (no events);
utilities/custom properties can't reach in. Anywhere else → the static icon.

Class/property prefixes (`fk-`, `animate`, `icon-animate`) are workspace
settings; the defaults above are the documented contract.

## Model

- `AnimationDef` — a reusable named keyframe recipe: `keyframes`
  (`{offset 0–100, declarations, easing}`), optional `timing` defaults,
  `normalizesPathLength` for draw-style defs (engine writes
  `pathLength="100"` on bound shapes so dash keyframes are 0–100 regardless
  of geometry).
- `AnimationBinding` — one applied animation: `animation` (def name),
  `target` (engine-owned marker class, e.g. `fk-anim-spin` — never svgID, so
  user renames can't break bindings), `trigger`
  (`continuous|hover|focus|active|parent-class:<cls>|manual`), and per-binding
  timing overrides (`delay` doubles as the timeline track offset).
- A per-icon "scene" is simply the icon's ordered `[AnimationBinding]` —
  there is no separate scene type (CSS has no master clock either).
- `AnimationSettings` — the cascade node (enabled, default trigger/timing,
  prefixes, reduced-motion policy). Resolution per emitted value:
  binding → def.timing → icon settings → workspace settings → standard.
  Default iteration is trigger-dependent: continuous ⇒ `infinite`,
  interaction ⇒ `1`.
- Storage: `Workfile.animations` + `WorkspaceSettings.animations`;
  `FileMeta.Meta.{animations, animationBindings, animationsEnabled,
  animationSettings}`. FileMeta rides inside the document as a RawNode, so
  every scene edit is snapshot-undoable and dirty-tracked for free, and
  export stripping already exists.
- Presets (spin, pulse, blink, draw, fade-in, bounce, shake, wiggle) are
  code templates copied into the workfile on demand — the compiler reads
  only workfile/FileMeta, one source of truth.
- Whole-icon binding = marker class on the `<svg>` root. One binding per
  element in v1 (comma-joined `animation-name` is v2); duplicate target in
  one icon is a lint error. Keyframe transforms are TRS components, never
  matrices.

## CSS emission

One RawNode `<style id="fekthor-animations">…</style>` inserted as the first
node; replaced/removed on every save by `AnimationEngine.applyingStyleBlock`.
Derived output — never parsed back (SVGReader skips it in `parseCSS`).
Determinism/idempotence: fixed emission order, `SVGNum` number style, CSS
guaranteed free of `<` and `&` (lint-enforced), inner indentation embedded in
the RawNode string → byte-identical re-saves with **zero SVGWriter changes**.

Collision safety (inline SVG CSS is document-global): workspace defs compile
to `@keyframes fk-<name>` byte-identically across every icon in the set —
duplicates on one page are harmless. File-local defs compile icon-scoped
(`fk-<iconSlug>-<name>`).

Gating rules per binding group the authored trigger's selectors with the
utility selectors into one `animation-name` rule, wrapped in
`@media (prefers-reduced-motion: no-preference)`. Inert longhands (duration,
timing, delay, iteration, direction, fill, plus `transform-origin` +
`transform-box: fill-box` for transform defs) sit in an always-on base rule.

## Export

Profile actions `strip-animations` (alias `static`; removes block + marker
classes; output byte-equals a never-animated export) and `bake-animations`
(alias `animated`; recompiles last from FileMeta). Runner strips FileMeta
AFTER actions (so they can consult bindings); `flatten` preserves
animation-bound groups. Default policy honors
`FileMeta.animationsEnabled ?? WorkspaceSettings.animations.enabled ?? true`.

## v1 animatable properties

`transform` (translate/rotate/scale), `opacity`, `fill`, `stroke`,
`stroke-width`, `stroke-dasharray`, `stroke-dashoffset`, `visibility`,
`transform-origin`. No `display`. Lint warns: bound node carrying a static
`transform` attribute (bake first — `transform-box` reinterprets it);
draw defs in an `outline-strokes` profile; translate keyframes with `resize`.

## Editor

- **Preview**: engine-side `AnimationInterpolator` (CSS keyframe semantics,
  UnitBezier + steps timing, iteration/direction/fill/delay, sRGB color
  lerp) drives per-node overrides injected into the canvas draw pass;
  clock = `TimelineView(.animation)`. Trigger simulation chips
  (Hover/Focus/Active/Gate). Playback never dirties the document.
- **Timeline**: bottom-docked resizable drawer (DAW-style) — tracks per
  binding, delay/duration bars, union diamonds collapsing per-property
  lanes, 1%-grid keyframe drag, segment easing popover with cubic-bezier
  pad, record-armed capture-from-canvas keyframing, spacebar transport.
- **Animation palette** (floating, 4-edit pattern): selection's bindings,
  asset/trigger/overrides, jump to timeline.
- **Library**: `Workspace ▸ Animations…` sheet (presets + user defs, mini
  0–100% timeline per def, live preview well); propagation via the
  stage→confirm→commit workspace controller pattern.

## Build phases & acceptance

1. **Engine model** — types + Workfile/FileMeta fields. ✓ Codable
   round-trip, old-schema decode, deterministic encode.
2. **Compiler** — `AnimationCSS` + reader guard + save hook. ✓ golden
   blocks, byte-idempotent re-save, cross-icon keyframes byte-equality,
   no classStyle pollution, foreign `<style>` untouched.
3. **Preview engine** — interpolator + controller + canvas overrides.
   ✓ goldens vs browser-sampled fixtures (bezier ε ≤ 1e-3, steps
   boundaries, direction/fill/delay matrix, implicit frames).
4. **Apply-preset path** — bind/unbind + palette + context menu. ✓ apply
   spin → plays on canvas → save → browser plays it.
5. **Timeline drawer (read/scrub)** ✓ tracks reflect scene; scrub matches
   browser at same t.
6. **Timeline editing** ✓ keyframe drag = one undo step; record mode never
   mutates base.
7. **Export actions** ✓ static-parity golden; flatten preserves bound
   groups.
8. **Library & polish** ✓ def edit propagates only changed files; docs.
