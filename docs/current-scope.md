# Current scope

The active ImageKid core scope is the non-AI media utility:

- image and basic video viewing;
- zoom and pan;
- colour inspection and palettes;
- crop and standard resize;
- annotations;
- image and video export;
- offline, native macOS behaviour.

Beyond the core utility, two opt-in Best Quality add-ons ship as downloaded
local runtimes: AI upscaling (Real-ESRGAN) and AI background removal (ISNet via
rembg). They are optional and must not block or shape the core non-AI
workflows. See `decisions.md` (D-013) and `ios-feasibility.md`.

The repository also has separate focused companion-app scope. ImageKid Upscale
and ImageKid Cutout have initial macOS targets. ImageKid Slicer is planned as a
third macOS companion for opening one composite image, manually defining
rectangular regions, and saving those regions as separate files. Companion
apps do not expand the core ImageKid window or change its first-release scope.
See `companion-apps.md` and `slicer.md`.
