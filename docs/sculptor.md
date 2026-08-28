# ImageKid Sculptor

## Status

**Working and packaged. Not signed, not notarised, not released.**

The reconstruction worker (`tools/sculptor-engine`), the shared Swift types
(`packages/ImageKidSculptorKit`) and the macOS app
(`apps/native-macos/Sources/ImageKidSculptor`) run end to end: import an image,
see it rated, generate locally, rotate the result, export GLB. The app installs
its own model — falling back from the R2 mirror to upstream Hugging Face, which
is ungated — and finds its own worker, so nothing needs configuring by hand.

`scripts/bundle_runtime.sh` packages a self-contained Python runtime into
`Contents/Resources/sculptor-engine` (918 MB), and the target is sandboxed on
the strength of it. A generation has been run entirely from that bundle.

`apps/native-macos/scripts/sign-sculptor.sh` signs the runtime's ~190 native
binaries and then the app, inside-out. The interpreter carries its own
entitlements, because it runs as a separate process and the app's do not reach
it.

What is *not* done: notarisation, which uploads to Apple and needs a Developer
ID Application certificate rather than the Apple Distribution one available
here. Reconstruction quality is good rather than perfect — see "Phase 0
findings" below and `tools/sculptor-engine/README.md`.

ImageKid Sculptor is a focused macOS companion app that turns one image containing one clear object into a complete, inspectable 3D model on the user's Mac.

The working product name is **ImageKid Sculptor**. The first release is intentionally narrow:

> Drop one image, generate one 3D model locally, rotate it to inspect every side, then export the model.

Sculptor is not a general 3D editor, photogrammetry suite, scene generator, CAD tool, or Blender replacement.

## Product goal

ImageKid already works with local images. Sculptor extends the same local-first idea into 3D for image libraries where each source asset represents a single subject: landmarks, vehicles, toys, furniture, animals, icons, products, and other isolated objects.

A primary motivating use case is the Tiko Media catalogue at `https://media.tikoapps.org/`: clean, stylised, mostly single-subject images should be convertible into reusable 3D assets for maps, globes, games, AR, and other interactive experiences.

The first milestone is not batch conversion. It is proving the smallest useful loop with one asset at a time.

## Core promise

Given one source image, Sculptor should:

1. load and validate the image;
2. isolate and normalise the main object;
3. reconstruct a complete 3D object locally;
4. infer plausible geometry and appearance for sides that are not visible in the source image;
5. clean and normalise the generated mesh;
6. show the result in an interactive 3D viewer;
7. export a `.glb` file.

The source image is never overwritten.

The generated back and hidden sides are **inferred**, not recovered from source pixels. Sculptor should aim for a coherent and useful 360-degree asset, not claim historical, engineering, CAD, or photogrammetric accuracy from one image.

## V1 scope

### Supported input

V1 accepts one local image at a time:

- PNG;
- JPEG/JPG;
- HEIC where supported by the system image stack;
- WebP where supported by the system image stack.

The ideal source contains:

- one primary object;
- the full object inside the frame;
- a transparent, plain, or easily removable background;
- a reasonably clear silhouette;
- enough visible structure to infer depth.

Sculptor should still attempt imperfect inputs, but it may warn when the object is cropped, the scene contains multiple competing subjects, or foreground isolation is unreliable.

### Best candidates

The initial product should be optimised around:

- landmarks and buildings;
- vehicles and boats;
- toys and stylised props;
- furniture and products;
- simple animals and characters;
- clay, cartoon, icon-like, or game-asset imagery.

These are particularly useful because the desired result is often a recognisable and coherent asset rather than an exact scan.

### Explicit non-goals for V1

Do not expand V1 into:

- text-to-3D;
- full-scene reconstruction;
- room or environment reconstruction;
- multiple-object scene parsing;
- rigging or animation;
- skeleton generation;
- manual mesh modelling;
- sculpting brushes;
- UV editing;
- material-node editing;
- photogrammetry from dozens of photographs;
- batch processing;
- cloud APIs or paid generation credits.

Multi-image input and batch processing are sensible later additions, but they must not delay the one-image workflow.

## User experience

The application should have one obvious path.

### Empty state

- Large image drop target.
- `Choose Image…` button.
- Short copy: **Turn one image into a 3D model on your Mac.**
- No account, project wizard, prompt field, or generation-credit UI.

### Ready state

After an image is selected:

- show the source image;
- show a small suitability status if useful (`Good`, `Okay`, or `Poor` candidate);
- enable **Generate 3D**.

Do not expose model names, Python, MPS, texture-resolution flags, inference steps, or other engine implementation details in the normal UI.

### Processing state

Show understandable stages rather than a generic spinner:

1. Preparing image
2. Isolating object
3. Reconstructing 3D
4. Building hidden sides
5. Cleaning model
6. Preparing preview

The exact internal engine may combine these steps, but the UI should describe what the user is waiting for.

Generation must be cancellable.

### Result state

The 3D viewer is the main result surface. Users must be able to:

- orbit freely around the object;
- zoom;
- pan where appropriate;
- reset the camera;
- inspect the back, left, right, top, and front by rotating the model;
- regenerate from the same input;
- choose another source image;
- export GLB.

Optional quick camera actions such as **Front**, **Back**, **Left**, and **Right** are acceptable if they make inspection faster without making the interface feel like a 3D editor.

V1 does not need user-facing mesh controls. The default should produce a useful asset without asking the user to understand topology.

## Reconstruction principle

Sculptor is a **single-image 3D reconstruction** app, not a depth-map extruder.

A depth-only approach would reproduce the visible face while leaving the hidden side undefined. That is not sufficient. The reconstruction engine must generate a complete 3D representation and make a learned prediction about unseen geometry.

For example, when the input shows a three-quarter view of a temple, the engine should infer the likely continuation of walls, towers, roof volumes, and rear structure. The result may not match the real temple exactly, but the object should remain structurally plausible when the user rotates behind it.

This hidden-side inference is a core product requirement, not an optional enhancement.

## Proposed V1 engine: SPAR3D

The primary V1 reconstruction candidate is Stability AI's **SPAR3D (Stable Point-Aware Reconstruction of 3D Objects from Single Images)**.

Why it fits Sculptor:

- it is specifically designed for single-image 3D reconstruction;
- it generates a complete mesh rather than only a visible depth surface;
- its point-cloud conditioning is intended to improve back-side prediction;
- it generates UV-unwrapped, textured 3D assets;
- its reference implementation exports GLB;
- the reference implementation includes experimental Apple Silicon / MPS support.

References:

- `https://github.com/Stability-AI/stable-point-aware-3d`
- `https://huggingface.co/stabilityai/stable-point-aware-3d`
- `https://stability.ai/news-updates/stable-point-aware-3d`

SPAR3D should be treated as the initial engine choice, not a permanent public product dependency. Keep an engine boundary so another local image-to-3D model can replace or complement it later without rebuilding the app UI.

### Current hardware considerations

The upstream SPAR3D documentation currently describes Apple Silicon MPS support as experimental and requires macOS 15.2 or newer for that path. It reports roughly 10.5 GB of memory in the normal path and approximately 7 GB in low-memory mode on supported backends, while also warning that MPS consumes more memory than CUDA and recommending CPU fallback below 32 GB unified memory.

Do not turn those upstream figures directly into final minimum-system requirements. Before release, benchmark the actual packaged Sculptor engine on representative Apple Silicon Macs and decide supported memory tiers from measured generation time, reliability, and thermal behaviour.

CPU execution may remain a development fallback but should not be presented as a good user experience until measured.

## Licensing and model distribution

SPAR3D model weights use the Stability AI Community License. At the time this plan was written, Stability AI describes free research, non-commercial, and limited commercial use for individuals and organisations below its stated annual-revenue threshold, with separate enterprise licensing requirements above that threshold.

The model repository is also gated on Hugging Face and the model weights are large (currently several gigabytes).

Therefore the release implementation must not casually assume that weights can simply be embedded in the application bundle. Before shipping:

1. verify the current Stability AI license and commercial registration requirements;
2. verify redistribution rights for the exact code and model-weight versions being shipped;
3. preserve required third-party notices;
4. decide whether the model is bundled, installed on first use, or imported by the user;
5. make any license acceptance explicit where required;
6. record the chosen model version/checksum in release documentation.

This is a distribution concern, not a reason to use a hosted API. Once the engine and model are installed, generation remains local.

## Phase 0 findings

The spike is done. Three things in the plan above changed as a result; the rest
held.

### The V1 engine is TripoSR, not SPAR3D

SPAR3D's weights are gated on Hugging Face behind an account and an acceptance
of the Stability AI Community License, whose revenue threshold pulls a
commercial release into separate enterprise terms. That makes it unverifiable in
CI and awkward to ship.

TripoSR does the same job — single image to a complete mesh with predicted
hidden geometry — under **MIT**, ungated. It is now the default. `spar3d.py`
still exists behind the same engine boundary for anyone who accepts the terms,
but it has never been executed, because its weights cannot be fetched without
credentials.

This is exactly the substitution the engine boundary was designed to absorb: no
change to the worker, the protocol, or the app.

### Orientation has to be corrected, and the user has to say how

Single-image reconstruction happens in the *input camera's* frame. Every
isometric Tiko Media asset therefore comes out tilted back by roughly the
camera's elevation. The plan's "orient the object consistently" cannot be
satisfied by declaring `+Y` up.

Two approaches were tried. Recovering the upright axis from geometry — taking
the object's largest flat surface as its base — **does not work reliably**: the
largest planar region on a real reconstruction is often the smooth back face the
engine invents, not the base. It corrected the Madrid palace and laid
`peace-palace` and `wat-pho` on their sides. It survives as an opt-in flag,
default off.

What works is two separate rotations, which were initially conflated:

**The engine's own convention.** TripoSR does not emit a Y-up mesh at all — the
subject's vertical axis comes out along Z, so an eye-level animal reconstructs
lying on its back. This was missed while the corpus was only landmarks, because
a wide diorama slab hides it. It surfaced immediately on animals: the yak, the
pelican and the gibbon all came out on their sides. A fixed **-90°** correction
inside the engine fixes every subject at once, and the yak becomes a properly
recognisable four-legged yak with horns and a shaggy coat.

**The camera's elevation**, on top of that, is a fact about the image: 0 for an
eye-level photo, about +30 for the isometric landmark renders.

The two compose exactly — -90 + 30 is the -60 first measured on landmarks — and
that arithmetic is what confirmed the split rather than a coincidence.

Because the camera height cannot be recovered from the image, the app asks: a
three-way **Seen from** control, remembered between launches and re-applied on
Regenerate. It defaults to eye level, since of 1,100 catalogue items 405
landmarks are isometric while 263 animals and 222 people are not, and an
imported photo is eye level too. That is a fact about the source image rather
than an engine detail, so it does not conflict with the rule against exposing
engine internals.

### The preview needs its own file

Apple's Model I/O, which backs SceneKit's asset loading, does not read GLB. As
the plan anticipated, the worker writes a preview adapter — the same geometry as
binary PLY with vertex colour — alongside the canonical GLB. The export the user
receives is unchanged by the viewer's limitations.

### Measured

Apple M3 / 24 GB / macOS 26.5, MPS, 256³ marching cubes. Ten landmarks: 10/10,
median 9.0 s. Nineteen assets spanning all six catalogue folders: **19/19,
median 9.8 s, 3.5 GB peak memory**. That is far below the 10.5 GB the SPAR3D
documentation quotes, so the upstream advice to fall back to CPU below 32 GB
does not apply here. Raising marching cubes to 384³ triples time and triangles
for a modest gain, because the triplane — not the isosurface — is the limit.

Quality by subject, with the right viewpoint:

- **Animals** are the strongest case, not the weakest as a landmark-only sample
  had implied. The yak has horns, a shaggy coat and four legs; the swan a curved
  neck and feathered wings; the penguin flippers and feet.
- **People** come out upright and recognisable, with hats, faces and clothing,
  and thin held props survive — the gondolier keeps his oar.
- **Landmarks and places** give legible massing and facades.
- **Geography** — islands, lakes — comes out as low flat lenses, which is
  roughly what those subjects are.
- **Flags do not work and cannot.** A flag is a 2D graphic with no object to
  reconstruct. Preparation already rates them `poor`.

The back face is always the softest side, very intricate subjects blur, and long
thin limbs soften. Solidly usable for maps, globes, game props and background
assets, and closer than that for animals and characters; short of a hero asset
with visible fine detail.

The stage weights in the protocol are still derived from stage ordering rather
than these timings, so the progress bar is uneven. That remains open.

## Local-only architecture

The core product requirement is that the image and generated model do not leave the Mac.

V1 should use a native macOS shell with a local reconstruction worker:

```text
ImageKid Sculptor (SwiftUI)
│
├── Import / source preview
├── Job state + cancellation
├── 3D preview
├── Export
│
└── SculptorEngineBridge
    │
    └── Local reconstruction worker
        ├── foreground preparation
        ├── SPAR3D inference
        ├── mesh cleanup
        ├── texture/material output
        └── GLB generation
```

No remote generation endpoint, API key, credit system, upload service, analytics dependency, or cloud fallback should be introduced.

## Native app boundary

Proposed target:

- target: `ImageKidSculptor`
- display name: `ImageKid Sculptor`
- proposed bundle id: `com.hakobs.imagekid.sculptor`
- category: Graphics & Design

Sculptor should be a separate app target rather than another tool mode in the main ImageKid editor. Its promise is sufficiently different and its model/runtime footprint is sufficiently large that it should not be forced onto users who only want the image editor.

Shared Swift code belongs in packages, not through app-to-app imports.

A possible future structure is:

```text
apps/native-macos/
└── Sources/ImageKidSculptor/

packages/
├── ImageKidInference/       # existing 2D inference boundary
└── ImageKidSculptorKit/     # Sculptor domain/job/preview/export types

tools/
└── sculptor-engine/         # local 3D reconstruction runtime
```

Do not add these folders until implementation starts; this section defines the intended boundary only.

## Engine process

For the first implementation spike, a Python + PyTorch worker using the MPS backend is the most practical way to run SPAR3D on Apple Silicon.

Prefer a dedicated worker process over embedding Python inside the Swift process. Benefits:

- model/runtime failures cannot directly crash the UI process;
- memory can be reclaimed by terminating the worker;
- Python dependencies remain isolated;
- the engine can be tested from the command line independently;
- a future native/Core ML/Core AI engine can replace the worker behind the same bridge.

Because model loading is expensive, the production app may keep a worker alive while Sculptor is open instead of spawning a fresh Python process for every generation.

Communication should be a small local protocol, preferably structured messages over stdin/stdout rather than a localhost HTTP server. A job message needs only source path, working directory, generation options, and job id. Progress and result messages should return stages, percentages where meaningful, error information, and generated artifact paths.

Never place large image bytes or model bytes in JSON messages; pass sandbox-authorised local paths to files owned by the job workspace.

## Input preparation

The app should normalise input before reconstruction.

Suggested path:

1. decode orientation correctly;
2. convert to a predictable working colour space;
3. identify the main foreground object;
4. preserve an existing alpha mask where it is already good;
5. otherwise use Apple Vision foreground/subject segmentation where suitable;
6. crop around the subject with consistent padding;
7. render the engine's expected square input size;
8. preserve the original source separately and immutably.

SPAR3D currently expects a 512×512 input internally. The app should own source preparation so engine swaps do not change user-visible import behaviour.

If foreground isolation fails, allow generation to continue when reasonable rather than forcing manual masking in V1.

## Mesh and asset normalisation

After inference, Sculptor should run a deterministic post-processing pass before preview/export.

At minimum:

- validate that the mesh contains geometry;
- remove clearly disconnected tiny fragments where safe;
- repair or reject invalid normals;
- place the object at a stable origin;
- orient the object consistently;
- place the lowest meaningful point on the ground plane;
- preserve generated UVs and textures;
- ensure the exported GLB can be reopened successfully.

Preferred asset convention for ImageKid/Tiko-compatible output:

- units: metres where meaningful, otherwise a normalised one-unit-scale asset with metadata documenting scale;
- up: `+Y`;
- forward: `-Z` where a meaningful forward direction can be inferred;
- origin: bottom-centre / ground contact;
- canonical export: GLB.

Automatic forward-direction inference is useful for vehicles, characters, and buildings, but V1 must not block export when forward direction is ambiguous.

## 3D preview

The preview is a product requirement, not merely debugging UI. A generation is only useful if the user can immediately rotate behind it and decide whether the inferred hidden geometry is acceptable.

The preview surface should provide:

- perspective camera;
- neutral studio lighting;
- simple ground/reference plane where useful;
- orbit gesture;
- scroll/pinch zoom;
- reset framing;
- correct textured/material rendering;
- transparent or neutral app background independent of the model texture.

Keep the canonical generated asset as GLB. If the selected Apple preview framework cannot directly consume the exact GLB features emitted by the engine, introduce a preview adapter that creates a temporary viewer-compatible representation. Do not silently change the canonical export just to satisfy the preview layer.

Potential native frameworks are RealityKit, Model I/O, and SceneKit; choose during the implementation spike based on actual GLB/material compatibility on the deployment target.

## Output

### V1

Mandatory output:

- `.glb`

Default filename:

- `{source-name}-3d.glb`

Default destination can be chosen during export. Do not overwrite an existing file without confirmation; use collision-safe numbering by default.

### Later

Potential additional exports:

- USDZ for Apple-native/AR workflows;
- OBJ for compatibility;
- STL for print-oriented workflows;
- optional lower-detail GLB variants.

Do not make these formats part of the first success criterion.

## Model storage

The 3D model weights are much larger than the current ImageKid 2D add-ons, so storage must be explicit and inspectable.

If Sculptor uses the ImageKid App Group, a possible location is conceptually:

```text
group.com.hakobs.imagekid/
└── Models/
    └── Sculptor/
        └── SPAR3D/<version>/
```

The app should expose model status and disk usage in Settings, with a **Remove Model** action. Removing the model must not delete generated user GLBs.

Do not redownload the model for every app launch or generation.

## Privacy and network behaviour

Sculptor follows ImageKid's local-first product rules:

- no account required;
- no image upload;
- no hosted inference;
- no per-generation credits;
- no telemetry required for generation;
- no remote fallback when local inference fails.

A network connection may be required only to obtain optional model/runtime files when the chosen distribution strategy uses on-demand installation. The UI must distinguish **installing the local engine** from **processing an image**. Once installed, normal generation should work offline.

## Failure handling

Each generation is a job with an isolated temporary working directory.

Expected recoverable errors include:

- unsupported or corrupt image;
- no useful foreground found;
- model not installed;
- insufficient free disk space;
- insufficient memory;
- worker crash;
- inference failure;
- invalid/empty generated mesh;
- preview conversion failure;
- export failure.

A failed generation must not leave a half-written destination GLB. Write temporary artifacts first and move the final file atomically when export succeeds.

The app should keep the source image loaded after a failure so the user can retry without re-importing it.

## V1 acceptance criteria

The first usable Sculptor build is successful when all of the following are true:

1. A user can drop one PNG/JPEG containing one object into the app.
2. Generation runs entirely on the Mac after the local engine/model is installed.
3. The reconstruction includes inferred geometry for sides not visible in the source image.
4. The app produces a textured 3D mesh rather than a 2.5D extrusion/card.
5. The result opens automatically in an interactive 3D viewer.
6. The user can rotate behind the model and inspect the generated back side.
7. The user can export the result as GLB.
8. The source image is never modified.
9. Generation can be cancelled or recovered from a worker failure without restarting the whole app.
10. No cloud API or paid generation service is involved.

## Implementation sequence

### Phase 0 — engine spike

Before building substantial UI:

1. get the official SPAR3D repository running on a representative Apple Silicon development Mac;
2. test MPS and CPU fallback behaviour;
3. run a small corpus of ImageKid/Tiko-style single-object images;
4. verify front, side, and especially back-side quality;
5. verify GLB material/texture output;
6. record generation time and peak memory;
7. identify required native/build dependencies;
8. confirm licensing/distribution constraints for the exact versions.

The spike should include simple stylised landmarks, vehicles, animals, and props rather than only photorealistic benchmark images.

### Phase 1 — local CLI contract

Create a deterministic local command that accepts one image and produces one GLB plus machine-readable progress/result output.

This establishes the engine boundary before Swift integration.

### Phase 2 — Sculptor app shell

Build the separate `ImageKid Sculptor` target with:

- drag/drop and Open panel;
- source image display;
- Generate 3D action;
- job progress/cancellation;
- local worker bridge;
- result handling.

### Phase 3 — 3D inspection

Add the native 3D viewer and verify generated GLBs/materials against the chosen preview path. The user must be able to inspect all sides comfortably.

### Phase 4 — export and hardening

Add:

- safe GLB export;
- worker crash recovery;
- model installation/status management;
- disk-space checks;
- memory/hardware warnings;
- signed/notarised packaging investigation.

### Phase 5 — quality pass

Build a representative regression corpus and record which source-image characteristics produce good, acceptable, or poor results. Use that evidence to improve preprocessing and candidate warnings.

Do not hide difficult cases by silently falling back to a cloud service.

## Future roadmap

Only after the one-image workflow is reliable:

### Batch mode

Process a folder or catalogue of isolated source images, show a queue, generate missing GLBs, and mark outputs as accepted/review/failed. This is the natural path for converting large media libraries such as Tiko Media.

### Multi-view input

Accept two or more real views of the same object for improved geometry when available.

### View-sheet import

Detect and split a single turnaround/reference sheet containing front/side/back panels, then use those views as multi-view input.

### Automatic quality review

Render standard front/right/back/left thumbnails after generation and flag obvious failures such as empty geometry, severe floating fragments, or extreme bounding-box distortion.

### Asset presets

Add game-oriented optimisation only when needed, for example automatic LODs or triangle targets. Keep the default experience one-click.

### Native inference exploration

Investigate future Core ML/Core AI or Metal-native execution when the required model operations can be supported without materially reducing output quality. The SwiftUI product should not depend on Python forever if a reliable native path becomes practical, but V1 should prefer a working local engine over premature conversion work.

## Product relationship

The ImageKid family should remain clear:

- **ImageKid** — inspect and edit images.
- **ImageKid Upscale** — upscale images locally.
- **ImageKid Cutout** — remove backgrounds locally.
- **ImageKid Sculptor** — turn one image of one object into a complete local 3D asset.

Sculptor should feel like the same family: focused, native, local-first, no subscription, and no requirement to understand the underlying AI stack.
