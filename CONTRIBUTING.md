# Contributing

ImageKid is at foundation stage. Discuss large product or architecture changes before implementation so the app remains a small media utility rather than a general editor.

## Local checks

```bash
npm install
npm run check
npm run native:build
npm run native:test
```

Native checks require macOS. Equivalent direct commands run from `apps/native-macos` with `swift build` and `swift test`.

## Expectations

- Keep all core behaviour local and offline.
- Prefer Apple frameworks over third-party native dependencies.
- Preserve source media; edits remain non-destructive until export.
- Store edit geometry in normalised media coordinates, not window coordinates.
- Keep native and website app boundaries separate; shared code belongs in `packages`.
- Add tests for coordinate conversion, rendering, file handling, UI behavior, and regressions.
- Keep the default viewer visually quiet and accessible through menus and keyboard.
- Do not add analytics, accounts, cloud processing, runtime downloads, or paid SDKs.

## Commits

Use focused Conventional Commits, for example `feat(native): add crop ratio preset` or `docs(website): clarify video scope`. Do not commit or push another contributor's work without explicit permission.
