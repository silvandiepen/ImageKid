# ImageKid agent guide

ImageKid is a monorepo containing a native macOS media utility and its static product website. Read this file before changing code.

## Sources of truth

Use these documents in order when claims differ:

1. `docs/implementation.md` for what exists now.
2. `docs/requirements.md` and `docs/product.md` for intended behavior.
3. `docs/release-boundary.md` for distribution status.
4. `docs/decisions.md`, `docs/architecture.md`, and `docs/roadmap.md` for context and sequencing.

Never present planned work as implemented. Video currently supports basic local playback only. There is no packaged, signed, notarised, or App Store release.

## Boundaries

- `apps/native-macos` owns Swift, SwiftUI/AppKit behavior, media processing, and native tests.
- `apps/website` owns the Vue product site and public web documentation. It must not become a second implementation of the app.
- `packages` is reserved for reusable code. Apps may depend on packages; apps never import from one another.
- Native work remains local-first: no accounts, telemetry, analytics, ads, uploads, cloud fallback, paid APIs, or runtime downloads.
- Keep image geometry in normalised media coordinates. Never export a screenshot of the viewport or overwrite source media implicitly.

## Vue website

Use Vue 3 Composition API, `<script setup lang="ts">`, strict TypeScript, relative local imports, Vite, Vue Router, `@sil/ui`, `open-icon`, and SCSS. Use `useBemm("block", { includeBaseClass: true })`, unscoped styles, and folder-per-component/composable scaffolds with model, test, index, and Readme files. No Tailwind, Options API, cross-app imports, or `highlight.js`.

Use `PillHeader`, `Button`, and other `@sil/ui` primitives where they fit. Icons come from `open-icon`; the ImageKid image-card mark is the sole custom inline SVG exception.

## CSS and color

- Consume `@sil/ui` spacing, type, radius, transition, shadow, background, and foreground tokens. Do not create a parallel global token set.
- Raw project brand colors belong only in the `@sil/ui` Vite theme palette and map to semantic tokens.
- Derived CSS colors must use `color-mix()` with only `--color-background`, `--color-foreground`, or `transparent`. Never derive from raw palette values or primary/secondary tokens.
- Do not define global `--color-surface`, `--color-surface-raised`, or `--color-muted` variables.
- No `rgba()`, gradients, raw `rem`/`em` in component CSS, `margin-bottom`, scoped styles, raw element selectors inside BEM blocks, or negative heading letter spacing.
- Use parent `gap` for sibling spacing. Preserve native scrolling and reduced-motion preferences.

## Validation

- Website: `npm run check` from the root.
- Native on macOS: `npm run native:build` and `npm run native:test`.
- Swift cannot be fully built on Linux because the package imports macOS-only frameworks; perform structural checks and rely on the macOS workflow there.
- Do not disable tests, suppress TypeScript errors, or replace real behavior with mocks. Fix root causes.

## Git and deploy

Use Conventional Commits if explicitly asked to commit. Never commit, push, force-push, skip hooks, or deploy without direct permission. Never add AI co-author trailers. Never add secrets. Production Pages deployment comes from `main`; development preview deployment comes from `development` through the checked-in workflow.

## Baseline companion guidance

Project rules above win where they are stricter. See:

- [`docs/agent-guidelines/AGENTS.md`](docs/agent-guidelines/AGENTS.md)
- [`docs/agent-guidelines/working-principles.md`](docs/agent-guidelines/working-principles.md)
- [`docs/agent-guidelines/stack-defaults.md`](docs/agent-guidelines/stack-defaults.md)
- [`docs/agent-guidelines/project-structure.md`](docs/agent-guidelines/project-structure.md)
- [`docs/agent-guidelines/vue-conventions.md`](docs/agent-guidelines/vue-conventions.md)
- [`docs/agent-guidelines/css-conventions.md`](docs/agent-guidelines/css-conventions.md)
- [`docs/agent-guidelines/design-conventions.md`](docs/agent-guidelines/design-conventions.md)
- [`docs/agent-guidelines/content-conventions.md`](docs/agent-guidelines/content-conventions.md)
- [`docs/agent-guidelines/git-conventions.md`](docs/agent-guidelines/git-conventions.md)
