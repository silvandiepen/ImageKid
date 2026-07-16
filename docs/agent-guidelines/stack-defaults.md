# Default Tech Stack for a New Project

These are defaults to reach for when starting something new and nothing dictates otherwise —
not requirements. Adjust per project.

## Frontend
- Vue 3 + Composition API + `<script setup lang="ts">`
- Vite as build tool (Nuxt only if SSR/marketing-site needs justify it)
- TypeScript, `strict: true`
- Vue Router for routing; Pinia for shared state (keep stores small)
- SCSS + BEM via `bemm`; no Tailwind
- `open-icon` for icons
- `@sil/ui` for shared UI primitives where the project can depend on it — check
  https://ui.sil.mt for docs before building a new UI component from scratch

## Backend / infra
- Cloudflare Workers as the default backend platform (Hono as the router/framework on top)
- Cloudflare D1 (SQL), R2 (object storage), KV, Queues as the default data/infra layer
- Prefer this over Supabase for new projects — Supabase is a legacy pattern in older repos,
  being actively migrated away from, not the current default
- Node 22+ (bump the floor per new project rather than retrofitting old ones; don't be
  conservative about the Node version floor)

## Package manager & monorepo tooling
- npm for a single-package repo (this is still the most common case)
- pnpm workspaces + Turborepo (or Nx) once a project is a genuine monorepo with multiple
  apps/packages — don't reach for this on a single-app project
- No Biome; ESLint flat config (`eslint.config.ts`) + Prettier

## Formatting
- 2-space indent, double quotes, semicolons — this is the direction newer/actively maintained
  repos have converged on. (Older repos use tabs + single quotes; don't retrofit those, but
  default to double-quote/semicolon style for anything new.)
- Named exports for composables/utils/services; default export only for `.vue` SFCs
  (re-exported through the folder's `index.ts`)
- `interface` over `type` for object shapes, especially props/model types

## Testing
- vitest (not jest) + `@vue/test-utils`
- Playwright for e2e when a project needs it

## Commits / releases
- Conventional Commits always (see `git-conventions.md`)
- semantic-release for packages meant to be published/versioned automatically (used in `ui`)
