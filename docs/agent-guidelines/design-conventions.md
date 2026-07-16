# Design Conventions

Default visual language for new products, based on `kod` and `lezin` — the two projects Sil
considers to have his best design principles — plus his own stated design taste. This governs
"what should this look like" decisions; `css-conventions.md` covers the mechanics (bemm, tokens,
no Tailwind, etc.) that implement it.

## Core stance

Restraint over spectacle. Whitespace and type hierarchy do the work that gradients, decoration,
and heavy motion do on generic "agency" sites. Nothing should look impressive in isolation —
it should look considered. Kod's own design doc puts it well: *"minimal, glossy, and highly
controlled... clean, approachable, and slightly luxurious rather than technical or
enterprise-heavy."*

The one-sentence version: **reduce the interface until only the meaningful parts remain, then
give those parts enough space, scale, and contrast to feel deliberate.** Closest recurring
references: Apple's native interfaces, Linear's restraint, spacious editorial websites, clean
Figma-style product layouts — but warmer and less technical than any of those on their own.

This means aggressive simplicity and strong visual hierarchy, not just "minimal" as a
color/decoration choice:
- Large, clearly separated sections with generous whitespace; low information density; one
  obvious purpose per area/screen.
- Strong typography and scale doing most of the hierarchy work — large, confident elements
  instead of many small controls, and instead of small cautious text.
- Clean asymmetrical layouts over repetitive card grids where the content allows it.
- Color used for meaning, hierarchy, or interaction — not decoration. Still one accent color
  per screen.

### Anti-patterns to actively avoid

These are the failure modes this taste is defined against — if a design is trending toward
one of these, pull back:
- Wrapping everything in its own card/box/container. Not every group of related content needs
  a bordered/shadowed container — whitespace and alignment can group things instead.
- The generic SaaS template: hero + three feature cards + gradient CTA button. If a landing
  page's structure would be indistinguishable from a template site, it's not considered.
- Cramped dashboards: counters, widgets, and metadata crammed edge-to-edge. Cut content before
  cutting spacing — if a screen feels tight, the fix is usually fewer things shown, not smaller
  gaps.
- Decorative icons, badges, labels, or status pills that don't carry real meaning — every badge
  should communicate something the user needs, not fill visual space.
- Borders separating every single element. Use a border only when it communicates real
  structure (a genuine boundary); prefer spacing/alignment to do the separating.
- "Gamey" UI: stars, confetti, reward/progression screens, glossy skeuomorphic buttons —
  unless the product is literally a game.
- Large amounts of explanatory copy visible by default — see `content-conventions.md`.
- Abstract marketing illustrations in place of real product screenshots/content. Show the
  actual thing.
- Adding more content/decoration when the real problem is spacing and composition — the fix
  for a design that "feels empty" or "feels busy" is almost always spacing/hierarchy, not more
  or less stuff.

## Hard rules

- **Never hijack scroll.** No Lenis, Locomotive Scroll, GSAP ScrollTrigger pinning, or anything
  that overrides native scroll physics.
- **Prefer CSS-native animation** — `@keyframes`, `transition`, scroll-driven CSS
  (`animation-timeline: view()`/`scroll()`) — over JS animation libraries. JS motion (GSAP,
  canvas/physics, Lottie) is a deliberate exception for projects whose brand register genuinely
  calls for tactile/playful interactivity, not a default.
- **Gradients are rare, and when used, subtle and near-monochrome** — a `color-mix()` tonal
  shift at the same hue, ~10–15% opacity, used functionally (a fade behind content, a hairline
  shimmer), never a bold multi-hue "AI gradient" sweep. Several of Sil's own products (kod) use
  no gradients at all — flat fills are the safe default.
- **One accent hue per product.** Never more than three brand hues total, and secondary/tertiary
  hues (if present) are reserved for specific semantic use (e.g. a health/status gradient), not
  general decoration. Accent color should appear in **under 15–20%** of visible elements at once.
- **Tint over outline for selection/active state.** Prefer a soft tinted background
  (`color-mix` against the accent) over a hard border or shadow to indicate
  selected/active/hover state. Kod's doc calls this pattern "central to the style."
- **Always respect `prefers-reduced-motion: no-preference`** for any decorative/entrance motion.
- Tokens/theming: see `css-conventions.md` — semantic tokens only, no raw hex/rem in components,
  no new global custom properties invented outside the shared token file if the project has one.

## Color

- Base palette is neutral and restrained: near-white surfaces (`#eef2f5`–`#f8f9fb` range for
  page background, pure or near-pure white for card/surface backgrounds), with one confident
  accent hue expanded into a light/dark/tint ramp (e.g. `--color-accent`, `--color-accent-light`,
  `--color-accent-dark`, `--color-accent-tint`) plus matching contrast-text tokens.
- Text tones: primary (near-black, e.g. `#111827`–`#171a24`), secondary (mid-gray, `#6b7280`–
  `#6e7587`), tertiary (light gray, `#9aa1b2`–`#9ca3af`) — three steps, not more.
- Borders: a single faint, cool-toned hairline color (`#e3e7ec`–`#e5e7eb`), used as 1px
  dividers rather than heavy strokes.
- Semantic colors (success/warning/danger/info) are separate from the brand accent — don't
  reuse the accent hue for status messaging.
- Muted/secondary text and subtle tints should be derived via
  `color-mix(in srgb, var(--color-foreground), transparent N%)` rather than separately
  hardcoded gray/tint values, so dark mode inherits correctly.
- Dark mode is a parallel, same-structure token set (invert neutrals, keep the same accent hue,
  push shadows to higher-opacity black) — not a different design. Pick one consistent mechanism
  per project (`data-color-mode="dark"` attribute or a `.dark` class) and use it everywhere in
  that project; don't mix approaches within one repo.

## Typography

- System font stack by default — not a premium/display foundry font:
  `'Inter', -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', Roboto, sans-serif`
  for UI-heavy apps; a plainer `system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto,
  sans-serif` stack for editorial/content sites. Only reach for a self-hosted/`@font-face`
  display font when the brand register explicitly needs a distinct voice (a consumer-health or
  playful brand) — that's the exception, not the starting point.
- Monospace stack for code/technical/numeric emphasis (codes, tokens, passwords):
  `'SF Mono', 'Fira Code', monospace` or similar — apply as `letter-spacing` emphasis
  (`0.08em`–`2px`) on top of it for legibility in things like OTP/password displays.
- Numeric scale for app UI: `11/13/15/17/20/24/32px`, weights `400/500/600/700`,
  line-height `1.2` (tight, headings) / `1.5` (normal) / `1.7` (relaxed, body copy). Fluid
  `clamp()`-based scale for editorial/marketing pages instead
  (e.g. `clamp(2rem, 4vw, 4rem)` for h1 down to `clamp(.75rem, 1vw, 1rem)` for eyebrow labels).
- Headings default to **semibold (600)**, never bold (700) — hierarchy comes from weight and
  color more than dramatic size jumps between heading levels.
- Small uppercase micro-labels (section titles, eyebrows, field labels) get wide letter-spacing
  (`0.04em`–`0.08em`); large display headings get slightly *negative* letter-spacing
  (`-0.01em`–`-0.02em`) instead. Tighten big text, loosen small caption text — apply both
  together, not just one.
- Don't chase extreme display-to-body scale ratios for their own sake — get hierarchy from
  confident-but-not-extreme scale contrast plus generous whitespace.

## Layout & spacing

- Whitespace is the primary structuring tool, not borders or color-blocked containers.
- Spacing between elements: use `gap` on flex/grid containers, not margin stacking (see the
  `no margin-bottom` rule in `css-conventions.md`). Margins are reserved for heading→body
  spacing inside a single prose block.
- Canonical content container: **max-width 1120px, 32px side padding, centered** — this exact
  combination repeats across marketing/landing layouts in multiple products; use it as the
  default unless a project has a specific reason not to.
- Prefer single-column, vertically-driven reading paths for content-led pages; reserve grids for
  genuinely modular content (galleries, card collections).
- Keep breakpoints few and pragmatic rather than a long ladder: a single ~720px mobile/desktop
  split works for editorial sites; `1024px`/`640px` tablet/mobile split works for app UI. Prefer
  fluid `clamp()`-based type/spacing over adding more breakpoint steps.
- Text-heavy content columns cap around **~64ch** for readability; widen only for
  galleries/archives.
- Border radius signals register — pick deliberately per project, don't default to
  pill-everything:
  - Small/flat (~4px): editorial/content sites — reads calm, serious.
  - Larger (8–24px), with pill shapes (`border-radius: 999px`) on primary CTAs: product/app UI
    — reads friendly, native-app-like. Kod's own scale: `sm 8px / md 12px / lg 16px`, plus
    larger `card 16px` / `input 12px` / `shell 24px` roles for bigger surfaces.

## Depth & components

- Shadows are either **extremely subtle or intentionally hard** — not the generic soft-SaaS
  middle ground of a medium blurry drop shadow on every card. A five-step subtle scale works
  well as the default:
  ```
  xs: 0 1px 2px rgba(0,0,0,0.04)
  sm: 0 2px 8px rgba(0,0,0,0.06)
  md: 0 4px 16px rgba(0,0,0,0.08)
  lg: 0 8px 32px rgba(0,0,0,0.10)
  xl: 0 16px 48px rgba(0,0,0,0.12)
  ```
  Dark mode swaps to higher-opacity black-based shadows (`0.2`–`0.4`) rather than lighter values.
  If a project wants shadow as an intentional graphic device instead (e.g. a hard-edged offset
  shadow for an editorial/poster feel), that's a legitimate deliberate choice — just don't land
  in between with soft-but-noticeable "generic app" shadows.
- Borders are used rarely, and only when they communicate real structure (an actual boundary
  between distinct regions) — not as a default separator between every element. Prefer
  whitespace/alignment to do the separating; when a border is used, keep it a single faint
  hairline (`--color-border-light`).
- Don't wrap everything in a card. Group related content with spacing/alignment first; reach
  for an actual bordered/shadowed card only for content that's genuinely a discrete, separable
  unit (a real card in a real grid of comparable items), not as a default container for every
  section.
- Native-feeling interaction patterns over bespoke widgetry: sheets, sidebars, list rows with
  contextual actions (swipe/hover-reveal actions, right-click/long-press menus) read as
  "considered" the way a generic modal-heavy or tab-heavy UI doesn't. Reach for these patterns
  before inventing a new custom control.
- Inputs: rounded, minimal/no visible border by default (`border: none; outline: none;` reset),
  focus indicated by a soft focus ring — `box-shadow: 0 0 0 3px color-mix(in srgb,
  var(--color-accent), transparent 75%)`, tightening on `:focus-visible`.
- Buttons: pill-shaped primary CTAs (`border-radius: 999px`) are fine but not mandatory —
  compact padding (`8px 20px`), semibold weight, filled with the accent color. Hover darkens
  toward the accent's dark variant plus a small lift (`transform: translateY(-1px)`) — never a
  heavy border or shadow change on hover. Secondary/tertiary actions drop the fill for
  ghost/outline treatments. Avoid glossy/skeuomorphic button treatments (inner highlights,
  gradient fills) entirely.
- Prefer real product screenshots/content over abstract marketing illustrations wherever a
  visual example is needed — show the actual thing, not a stylized stand-in for it.

## Motion

- Short and snappy: `150ms`/`200ms`/`300ms` (fast/base/slow), always plain `ease` — no custom
  cubic-bezier or spring physics by default. (A consistent custom easing curve reused everywhere,
  e.g. a bouncy `cubic-bezier(.06,.74,.48,1.05)`, is a legitimate taste option for a project that
  wants to feel more distinctive — but pick one curve and reuse it project-wide, don't mix.)
- Apply a global `transition: background-color 200ms ease, color 200ms ease;` on `html` for
  smooth light/dark toggling.
- Motion is hover-triggered and functional (color/background changes, small lifts, gap
  widening on hover, icon fades) — not showcase choreography.
- Entrance animation (landing hero, etc.) is the one place beyond simple hover states worth
  animating: short `@keyframes` (~300–700ms, plain ease), staggered via `animation-delay` in
  small increments (~60–80ms) between elements — always gated behind
  `@media (prefers-reduced-motion: no-preference)`.
- Data-visualization elements (progress rings, charts) can use longer, purpose-built durations
  (`0.3s`–`1s`) outside the standard token scale — treat this as its own category, not a
  precedent for general UI motion.
- No page-transition/router animation framework by default — navigation should be instant;
  reserve motion for micro-interactions and a single hero entrance if any.

## Quick checklist before calling a design "done"

- [ ] No `<style scoped>` — bemm + unscoped SCSS, tokens from `@sil/ui` only
- [ ] No new global tokens invented outside the shared token/variables file
- [ ] No scroll-hijacking library
- [ ] Gradients absent, or subtle/monochrome and functional only
- [ ] One accent hue, used in under ~20% of visible elements
- [ ] Selection/active state uses tint, not outline
- [ ] Motion respects `prefers-reduced-motion`
- [ ] Hierarchy is readable from whitespace/scale alone (squint test), not from decoration
- [ ] Font stack matches the project's register (system-first unless brand explicitly wants a
      display face)
