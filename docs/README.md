# ImageKid documentation

This directory is the source of truth for the product and implementation.

## Documents

- [Product definition](product.md): problem, audience, scope, principles, use cases, non-goals, and success criteria.
- [Requirements](requirements.md): functional, quality, privacy, accessibility, image, video, annotation, export, and upscaling requirements.
- [User experience](ux.md): empty state, viewer, hover controls, menu structure, tool modes, playback, and export flows.
- [Architecture](architecture.md): native stack, session model, coordinate systems, media pipelines, rendering, concurrency, and persistence.
- [Offline AI upscaling](upscaling.md): bundled models, runtime design, tiling, video processing, licensing, limits, and model evaluation.
- [Decisions](decisions.md): accepted product and technical choices with rationale and consequences.
- [Testing](testing.md): unit, visual, media, model, accessibility, performance, and release testing.
- [Roadmap](roadmap.md): staged implementation plan and deferred ideas.

## Rules

- `MUST`, `SHOULD`, and `MAY` are used deliberately.
- User-visible behaviour changes must update the relevant product, requirement, or UX document.
- Architectural changes must append or supersede a decision in `decisions.md`.
- No feature may introduce an online dependency without explicitly reversing the offline-only product decision.
- Every bundled binary and model must be listed in `THIRD_PARTY_NOTICES.md` with its license and source.
- The default viewer must remain clean. New features should use progressive disclosure rather than permanent editor chrome.