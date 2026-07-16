# Sil van Diepen — Baseline Agent Instructions

This is the baseline `AGENTS.md` for new projects. It was distilled from patterns observed
across ~90 existing repos (`edit`, `home`, `geo`, `lezu-platform`, `status`, `mikki`, `skumize`,
`ui`, and others) — both from their own `AGENTS.md`/`CLAUDE.md` files and from their actual code.

Copy this file (and whichever companion files apply) into a new project's root as `AGENTS.md`,
then trim/adjust for that project's actual stack. Treat it as a strong default, not a law —
project-specific `AGENTS.md` always wins if it says something different.

Companion files in this folder, load as relevant:
- `git-conventions.md` — commit style, branching, commit/push permission rules
- `vue-conventions.md` — component/composable scaffold, Vue-specific rules
- `css-conventions.md` — design tokens, bemm, spacing, dark mode
- `design-conventions.md` — visual taste/aesthetic (based on `kod`/`lezin`): restraint, hierarchy via whitespace/type, anti-patterns to avoid
- `content-conventions.md` — voice/tone for copy, and mandatory pages (support, terms, privacy) every public site needs
- `stack-defaults.md` — default tech choices for a new project
- `project-structure.md` — folder layout conventions
- `working-principles.md` — how to behave as an agent in Sil's repos (root-cause fixing, no mocking, etc.)

## Quick summary of the person

Sil is a senior full-stack/Vue developer who builds and reuses his own small ecosystem of
packages (`bemm`, `open-icon`, `@sil/ui`) rather than reaching for generic third-party
equivalents. He runs many small-to-mid personal/client projects in parallel, favors
greenfield-clean code over backwards compatibility, and has a strong, consistent aesthetic
for CSS (semantic design tokens, no Tailwind, no `margin-bottom`). He is moving his backend
stack from Supabase toward Cloudflare Workers/D1/R2/KV/Queues. Conventional Commits and a
"never fake it, fix root causes" ethic are near-universal across his repos.

## The single most load-bearing convention

Every Vue component and composable gets its own folder with a fixed file set:

```
ComponentName/
  ComponentName.vue        # template + <script setup lang="ts"> + unscoped BEM/SCSS styles
  ComponentName.model.ts   # exported Props interface (and other local types)
  ComponentName.test.ts    # vitest + @vue/test-utils
  index.ts                 # export { default } from "./ComponentName.vue"
  Readme.md                # one-sentence description
```

```
useName/
  useName.ts
  useName.model.ts
  useName.test.ts
  index.ts
  Readme.md
```

This appears independently in multiple repos (`edit`, `home`) and both have built Claude
Code skills (`/scaffold-component`, `/scaffold-composable`) to generate it. Prefer building
equivalent skills for a new project rather than creating components ad hoc.

## Hard rules (no exceptions, seen verbatim across repos)

- **Never** include `Co-Authored-By: Claude` (or similar) in commit messages.
- **Never** `git commit` or `git push` without explicit user instruction (the words "commit"
  or "push"/"deploy" from the user, not inferred from context).
- **Never mock** in place of a real implementation — implement the real thing, or say you can't.
- **Do not work around errors** (removing imports, catching-and-ignoring, disabling checks) —
  fix the actual root cause. Never remove/disable a failing test or check to make it pass.
- **No Tailwind**, unless a project explicitly opts in. Default is SCSS + BEM (via `bemm`),
  never `<style scoped>`.
- **Use `@sil/ui`'s custom properties for all tokens** (color/space/font-size/radius/shadow) —
  never define a parallel global token set. Component-scoped local variables are fine; new
  *global* custom properties outside `@sil/ui` are not — see `css-conventions.md`.
- **No raw `rgba()`, `rem`, `em`, or `margin-bottom`** in component styles — see `css-conventions.md`.
- Prefer **TypeScript strict mode**, `interface` over `type` for object/props shapes, and avoid `any`.

## Default stance when unsure

Priority order when conventions conflict: **correctness/security > architecture clarity >
maintainability > extensibility > developer convenience**. Avoid premature complexity and
avoid designing for hypothetical future requirements — this mirrors Sil's own stated priority
order in `geo/AGENTS.md` and `status/AGENTS.md`.
