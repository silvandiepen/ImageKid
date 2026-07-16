# Contributing

ImageKid is at foundation stage. Discuss large product or architecture changes before implementation so the app remains a small media utility rather than a general editor.

## Local checks

```bash
swift build
swift test
```

## Expectations

- Keep all core behaviour local and offline.
- Prefer Apple frameworks over third-party dependencies.
- Preserve source media; edits remain non-destructive until export.
- Store edit geometry in normalised media coordinates, not window coordinates.
- Add tests for coordinate conversion, rendering, file handling, and regressions.
- Keep the default viewer visually quiet and accessible through menus and keyboard.
- Do not add analytics, accounts, cloud processing, runtime downloads, or paid SDKs.

## Commits

Use focused conventional commits, for example:

- `feat: add crop ratio presets`
- `fix: preserve sampled pixel across zoom`
- `test: cover rotated image coordinates`
- `docs: clarify video export scope`
