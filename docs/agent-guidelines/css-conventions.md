# CSS / Styling Conventions

This is one of the most consistent, deliberate parts of Sil's style — treat these as hard
defaults, not suggestions, unless a project explicitly says otherwise.

## No Tailwind

Default is SCSS with BEM methodology, using **bemm** (Sil's own BEM class-name helper) for
generating class names in Vue components. Tailwind is explicitly rejected as a default in
multiple projects' own instructions — don't introduce it unless the user asks for it by name.

Always call it as:

```ts
const bemm = useBemm('block', { includeBaseClass: true });
```

`'block'` is the component's BEM block name (kebab-case, matching the component). Always pass
`{ includeBaseClass: true }` — don't omit the options object or use a different option set.

Watch the bemm modifier-array gotcha: use
`bemm("elem", ["", isSelected ? "selected" : ""])`, not an object form like
`bemm("elem", { selected: isSelected })` — the array form is the correct usage.

## Never use `<style scoped>`

Always write unscoped SCSS and rely on BEM (via `bemm`) for isolation instead of Vue's scoped-style
attribute selectors. This applies to **every** component, not just shared/library ones — app
components included. Scoped styles fight the BEM naming discipline (you end up with both a
`data-v-*` attribute selector and a BEM class doing the same job) and make it harder for a
consumer/future component to override something predictably. A correctly BEM-named class is
already scoped by convention — the block name is the namespace.

## Always use BEM, properly nested in SCSS

Every component gets one BEM block, generated via `bemm`, with proper SCSS `&` nesting —
never flat/repeated class selectors, never ad hoc one-off class names outside the block:

```scss
.component-name {
  display: flex;

  &__element {
    color: var(--color-text-primary);

    &--modifier {
      color: var(--color-accent);
    }
  }

  &--variant {
    background: var(--color-surface-raised);
  }
}
```

Indent nested selectors properly (2 spaces, matching the project's general indent) so the
block/element/modifier structure is visually legible at a glance — don't collapse nesting or
mix nested and non-nested selectors in the same file.

## Never style raw HTML elements — always target a class

Styling a bare element selector, especially descended from a BEM class, is forbidden:

```scss
// Forbidden:
.home-view__process div {
  ...
}
.home-view__process p {
  ...
}
```

Every element that needs styling gets its own BEM element class instead
(`.home-view__process-item`, `.home-view__process-text`, etc.), even if that means adding a
class to a `div`/`span`/`p` that would otherwise be "just a wrapper." Element selectors are
fragile (they break the moment markup changes), fight the BEM naming discipline, and make
specificity/overrides unpredictable. The only acceptable bare-element selectors are truly
global resets (e.g. in a base/reset stylesheet, not component SCSS) — never inside a component
block.

## Use `@sil/ui`'s custom properties — never invent your own global set

`@sil/ui` ships a full set of design tokens as CSS custom properties (`--color-*`, `--space-*`,
`--font-size-*`, `--border-radius-*`, `--shadow-*`, `--transition`, etc.). These are the only
global custom properties a project should have. Consume them directly in component SCSS —
do **not**:
- redefine your own `_variables.scss`/`_tokens.scss` with a parallel color/spacing/radius scale,
- re-declare a subset of `@sil/ui`'s tokens under new names "for this project,"
- hardcode a raw value where a `@sil/ui` token already exists for that purpose.

(Both `kod` and `lezin` drifted into defining their own large parallel token files instead of
relying on `@sil/ui` — that happened because the pattern hadn't been enforced yet, not because
it's a good idea. Don't repeat it in new projects.)

The only custom properties a project should define itself are **component-scoped, local
variables** — set on a component's own root/block selector, used only within that component,
for values that are genuinely component-specific and don't belong in the shared token set
(e.g. a prop-driven color override, per-component layout numbers). Never add a new *global*
custom property outside of `@sil/ui`'s own token set.

## Design tokens, not raw values

- Never reach for a raw color (`#fff`, `red`) — use `@sil/ui`'s semantic color tokens
  (`--color-primary`, `--color-danger`, etc.), not a raw hex or a base-palette variable.
- Never use `rgba()` for transparency — use `color-mix(in srgb, var(--color-x), transparent N%)`
  against a semantic token instead.
- Never hardcode spacing or font sizes as raw `rem`/`em`/`px` — use `@sil/ui`'s `var(--space-*)`
  and `var(--font-size-*)` tokens.
- Shadows/transitions: use `@sil/ui`'s tokens (`--shadow-*`, `--transition`,
  `--transition-fast`) rather than inline values.
- Dark mode should fall out of `@sil/ui`'s token system automatically — avoid manual
  `[data-color-mode]` override blocks per component.

## Spacing

**Never use `margin-bottom`.** Do spacing between siblings by setting `gap` on the parent
flex/grid container instead. This is a strict, repeated rule across projects.

## Component color theming (when a component needs a color variant)

Don't create per-variant modifier classes just to swap a color (`&--success`, `&--warning`).
Instead expose the color as a prop that sets **component-scoped** custom properties on the
component's own root, sourced from `@sil/ui` tokens — not a new global:

```
--component-color: var(--color-<token>);
--component-text: var(--color-<token>-contrast);
```

## Public vs internal custom properties (design-system / shared UI packages specifically)

For a project that is itself a shared UI/design-system package (like `@sil/ui` itself), use a
two-tier naming scheme for the component-scoped properties it exposes: `--int-<component>-*`
for internal, component-owned properties that implementation details rely on, vs
`--<component>-*` for the public API surface a consumer of the component is meant to override.
Both tiers are still scoped to that component — this is not an exception to the "no new
globals" rule, it's how a component's own local variables are organized.

## SCSS

- Use `&` nesting for BEM elements/modifiers, indented consistently (2 spaces) — never flatten
  nested selectors into repeated top-level class rules.
- Avoid inline `style="..."` attributes — put styling in the component's stylesheet.
