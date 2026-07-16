# Deferred upscaling research

AI upscaling is not part of the current ImageKid scope, build, architecture, requirements, dependencies, or roadmap.

No model, Core ML package, provider interface, tiling system, video inference pipeline, attribution requirement, or upscaling control should be introduced while the non-AI image and video workflows remain incomplete.

The feature may be reconsidered after:

- image viewing, colour inspection, crop, resize, annotation, undo, and export are stable;
- basic video inspection, processing, annotation, and export are stable;
- the signed offline macOS application has been released and measured;
- a concrete user need justifies the application size, testing burden, licensing work, performance cost, and maintenance surface.

Any future proposal must remain fully offline and may not depend on cloud processing, paid APIs, accounts, runtime downloads, Python, or separately installed runtimes.
