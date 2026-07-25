# Documentation

ImageKid is currently an offline native macOS image utility with basic video viewing. It also ships optional, opt-in local Best Quality add-ons for AI upscaling and background removal that download a model runtime on demand and run it on-device.

- [Product definition](product.md) — purpose, audience, scope, principles, and non-goals.
- [Requirements](requirements.md) — functional and quality requirements for the core application.
- [User experience](ux.md) — media-first window, floating controls, tool behaviour, and native interaction.
- [Architecture](architecture.md) — current Swift package structure and intended rendering boundaries.
- [Implementation status](implementation.md) — what works in the current scaffold and what remains.
- [Decisions](decisions.md) — product and technical decisions.
- [Testing](testing.md) — validation strategy and release gates.
- [Roadmap](roadmap.md) — implementation order for images, then basic video processing.
- [Upscaling](upscaling.md) — standard and Best Quality upscaling paths.
- [Companion apps](companion-apps.md) — status and roadmap for separate ImageKid Upscale and ImageKid Cutout batch apps.
- [iOS feasibility](ios-feasibility.md) — whether upscaling and background removal can move to iOS, and the Core ML direction.
- [Build](build.md) — native and website development commands.
- [Website](website.md) — routes, content ownership, domains, and Cloudflare Pages deployment.

Per-app deep docs:

- [Fekthor](fekthor/EDITOR-PLAN.md) — the vector editor plan; also [Animations](fekthor/ANIMATIONS.md).
- [Inka](inka/README.md) — the drawing & illustration app; the [brush engine](inka/BRUSH-ENGINE.md) and [architecture](inka/ARCHITECTURE.md).
