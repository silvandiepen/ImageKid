# ImageKidiOS — Guipetto contract

This directory tells [Guipetto](https://guipetto.dev) how to run ImageKidiOS and what
workflows are worth running. It is committed with the source, reviewed in pull requests, and
read by both people and coding agents. Guipetto's desktop application is never the only place
any of it exists.

Guipetto builds the `ImageKidiOS` scheme of `apps/native-ios/ImageKidiOS.xcodeproj`.

## Layout

```text
.guipetto/
├── project.yml       how to obtain and launch the application
├── environments/     the conditions a flow runs under
│   └── default.yml
├── flows/            the workflows worth running
│   └── caption-a-photo.yml
├── branding/         what generated screenshots and demos should look like
│   └── default.yml
├── fixtures/         deterministic seed data       (none — see below)
├── safety.yml        destructive and externally visible targets (not declared yet)
└── README.md         this file
```

## How a run gets a picture to edit

ImageKid opens pictures through `PhotosPicker`, which is an out-of-process sheet: nothing in
it publishes an identifier this repository controls, so no flow can drive it. Runs therefore
launch with ImageKid's own hooks (`UITestSupport.swift`):

- `--uitest` wipes the persisted panel and canvas state and stops UIKit animations;
- `--demo-image` opens a generated sunset picture straight into the editor.

`--demo-image` is the screenshot counterpart of the XCUITest suite's `--uitest-image`, which
opens flat colour quadrants that are good for reading a failed test and bad for a screenshot.
Both are generated in-process, so every run edits exactly the same picture and no fixture
files are needed.

## Getting to a first passing flow

1. **Give the interface stable identifiers.** A flow names elements by
   `accessibilityIdentifier`, never by visible copy or position. Find the ones that are
   missing with:

   ```bash
   guipetto identifiers .
   ```

   It launches the application, reads its accessibility tree, and lists every interactive
   element with no stable identifier — with a suggested `area.entity.action` name for each.

2. **Add the identifiers** in `area.entity.action` form: `game.new`, `settings.sound.toggle`,
   `deck.stock.draw`. They describe product meaning, stay stable across localisation, and are
   never derived from a visible string.

3. **Write a flow** in `.guipetto/flows/<id>.yml` naming those identifiers. The full step and
   assertion vocabulary is in Guipetto's `docs/AUTHORING.md`; the short version:

   ```yaml
   schemaVersion: 1
   id: start-game
   title: Start a new game
   goal: Show a player starting a fresh game

   preconditions:
     environment: default

   steps:
     - tap: game.new
     - waitFor: game.board

   assertions:
     - visible: game.board

   safety:
     externalEffects: false
   ```

4. **Check it, then run it.**

   ```bash
   guipetto validate .
   guipetto run start-game .
   ```

`guipetto validate` reports the exact file, line and field for every problem, with a suggested
correction. Fix, re-run, repeat — that loop is the whole authoring experience.

## Rules for this repository

Add this to the repository's own `AGENTS.md` so every agent working here reads it:

```markdown
## Guipetto

This project is automated through `.guipetto/`. See `.guipetto/README.md`.

When changing user-facing UI:
- preserve or add stable accessibility identifiers in `area.entity.action` form;
- never derive an identifier from visible copy;
- update affected flows and fixtures in the same change;
- run `guipetto validate .`;
- run the affected flows before claiming the change is done.
```

## What does not belong here

Screenshots, videos, run artefacts, build products, and caches. Guipetto keeps those in its
own local workspace; this directory holds intent only.
