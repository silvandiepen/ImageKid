# Project Structure Conventions

## Single-app layout

```
src/
  components/    # folder-per-component, see vue-conventions.md scaffold
  composables/   # folder-per-composable
  stores/        # Pinia, kept small
  views/  (or pages/)
  router/
  utils/
  types/  (or models/)
  services/
```

## Monorepo layout

```
/apps        # independent, deployable applications
/packages    # shared code: ui, shared types/schemas, data adapters, etc.
/tools       # internal scripts/tooling, not shipped
/docs        # architecture docs, decisions, specs
```

Rule, consistent across every monorepo checked: **apps depend on packages, never on each
other.** If two apps need the same logic, it belongs in a package, not a cross-app import.

Recurring shared package names worth defaulting to: `packages/ui` (shared components),
`packages/shared` (shared types/schemas/utils).

## Data-access boundary (when wrapping an external dataset or API)

Don't let app code import a raw external dataset/API client directly. Wrap it in an internal
adapter package exposing normalized functions (e.g. `getAllCountries()`,
`getCountryByCode()`), so the rest of the app isn't coupled to the raw shape and the source can
be swapped later without a rewrite (seen in `geo`'s `geo-data` package wrapping `sil-data`).

## Doc-hierarchy pattern (optional, for greenfield/spec-first projects)

For projects that benefit from an explicit spec (product tools, anything with real product
ambiguity), a numbered doc hierarchy works well and has been used successfully:

```
AGENTS.md          # entry point, points to the rest in read order
DOCTRINE.md         # product tone/principles
SPEC.md             # canonical current spec
docs/
  00-...md
  01-...md
  decisions.md      # log of assumptions made when the spec doesn't cover something
```

Not every project needs this — reserve it for projects where the product itself is still
being defined and decisions need a paper trail. For a simple project, a single `AGENTS.md` is enough.

## Assumption discipline

If a project's product/requirements aren't fully defined and you have to make a judgment
call, don't just silently pick one — note the assumption (in `docs/decisions.md` if that
pattern is in use, otherwise in the PR description or a comment to the user).
