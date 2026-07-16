# Vue Conventions

Vue 3 + Composition API + `<script setup lang="ts">` is the default and near-universal choice
across every active repo — no React, no Svelte, no Options API in modern code. Vite is the
default build tool (Nuxt only for a handful of marketing-site-style repos).

## Component/composable scaffold (always use this)

```
ComponentName/
  ComponentName.vue        # template + <script setup lang="ts"> + unscoped BEM/SCSS styles (see css-conventions.md)
  ComponentName.model.ts   # exported Props interface, emits types, other local types
  ComponentName.test.ts    # vitest + @vue/test-utils, test behaviour not implementation
  index.ts                 # export { default } from "./ComponentName.vue"
  Readme.md                # one sentence: what this component is for
```

```
useName/
  useName.ts
  useName.model.ts
  useName.test.ts
  index.ts
  Readme.md
```

Types/interfaces live in the `.model.ts` file, not inline in the `.vue`/`.ts` file.

## Naming

- Components/folders: `PascalCase`
- Composables/utilities: `camelCase` (`useThing.ts`)
- Asset files: `kebab-case`

## Imports

Order: Vue/core imports → third-party libs → local/relative imports.

## Dumb UI vs smart feature components

- Keep UI components dumb: props in, events out, no store/data access, no auth-awareness.
- Feature components are the ones allowed to be smart — data loading, store coordination,
  auth-aware behavior. Don't blur this line by giving a UI-primitive component a store dependency.
- Only use UI primitives from the project's shared UI package (`packages/ui` or `@sil/ui`
  where applicable) — don't create new one-off primitives without checking it doesn't
  already exist.

## State

- Pinia for shared/global state. Keep stores small and focused; if a store is growing large,
  pull session/derived logic out into a composable instead of one giant store.

## Reuse before building

Before adding a new component/composable/util, check whether the codebase already solves the
problem (existing component, existing composable, shared package). Extend/reuse existing
patterns rather than creating a parallel implementation. When you do touch a file, clean up
dead/unused code in it as long as it's safe and in scope.

## Popup/modal pattern (when a project needs global overlays)

A global `popupService` (provided/injected via `inject('popupService')`) drives a single
`Popup` component mounted once near the app root, plus a `PopupWrapper` component for
overlays that are always inline rather than dynamically triggered. This exact pattern repeats
across multiple repos (`lezu`, `lezu.dev`, `edit`'s UI package) — reuse it rather than
inventing a new modal system per project.

## Documentation

- JSDoc/TSDoc on exported functions: `@param` per parameter, `@returns`. Applied inconsistently
  in practice across sampled repos, but it's the stated expectation — hold to it for anything
  exported from a shared package or composable.
- Functions needing more than two inputs take a single typed object parameter, not more than
  two positional arguments.

## Testing

- vitest is the default test runner (not jest — jest only appears in old/legacy repos).
- Playwright for e2e/system tests when a project needs them.
- Test behavior, not implementation. Don't mock pure functions or things that don't need mocking
  — prefer exercising the real implementation.
- Behavior-bearing functions (services, repositories, composables with logic) need unit tests;
  route/page-level tests don't substitute for them.
