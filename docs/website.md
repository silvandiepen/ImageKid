# Website

## Purpose and content ownership

The static website at `imagekid.hakobs.com` explains the native app without duplicating its implementation. Product claims follow `docs/implementation.md`; intended behavior follows `docs/product.md` and `docs/requirements.md`; release language follows `docs/release-boundary.md`.

Routes:

- `/` — product promise, workflow, current capabilities, privacy, and source-build status.
- `/features` — explicit current and incomplete feature ledger.
- `/docs` — documentation index.
- `/docs/getting-started` — macOS requirements and real build commands.
- `/docs/workflows` — menus, keyboard controls, edits, export, and limitations.
- `/docs/architecture` — native/web boundaries and technical structure.
- `/docs/roadmap` — current, next, and deferred work.
- `/support`, `/privacy`, `/terms` — mandatory support and policy pages.
- `/not-found` — explicit fallback target.

## Technical foundation

`apps/website` is a Vue 3 SPA built with Vite and strict TypeScript. It uses Vue Router, SCSS, BEM via `bemm`, `@sil/ui` primitives and theme generation, and `open-icon` through UI icon APIs. The reusable components and composables follow the folder-per-component convention. `_redirects` provides SPA routing; `_headers` provides practical static-site security headers.

The theme bootstrap in `index.html` runs before the app module and sets both `data-theme` and `data-color-mode` to avoid a light/dark flash.

## Local development

From the repository root:

```bash
npm install
npm run site:dev
npm run check
npm run site:build
```

The output is `apps/website/dist`.

## Deployment and domains

Cloudflare Pages serves the static output. GitHub Actions deploys:

- `development` to the Pages project `imagekid-dev` for development review.
- `main` to the Pages project `imagekid` for production at `imagekid.hakobs.com`.

The workflow uses `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` repository secrets. Do not put credentials in source or trigger a deployment without explicit permission. Cloudflare may process normal request metadata when serving the site; the site does not add analytics or advertising trackers.
