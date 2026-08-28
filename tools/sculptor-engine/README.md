# Sculptor reconstruction engine

Local single-image-to-3D worker for **ImageKid Sculptor**. Takes one image
containing one clear object and produces one GLB with inferred hidden sides,
entirely on the user's Mac.

The app that drives it is `apps/native-macos/Sources/ImageKidSculptor`; the
shared Swift types are in `packages/ImageKidSculptorKit`. Product plan:
[`docs/sculptor.md`](../../docs/sculptor.md).

## What this does and does not own

The worker reconstructs. It does not download.

Model weights are installed by the app into the shared App Group, the same way
ImageKid already installs the Best Cutout and Best Upscale Core ML models (see
`CompanionCoreMLModels.swift`). When weights are absent the worker reports a
recoverable `modelNotInstalled` error and the app offers the download. Nothing
here ever reaches the network.

Vision foreground segmentation is likewise the app's job; pass the result as
`maskPath` and the worker will honour it. Without one, the worker falls back to
a usable alpha channel, and failing that reconstructs the whole frame rather
than forcing manual masking.

## Engines

| Engine | Licence | Gated | Default |
| --- | --- | --- | --- |
| `triposr` | MIT | No | **Yes** |
| `spar3d` | Stability AI Community | Yes | No |

`docs/sculptor.md` proposed SPAR3D. Its weights turned out to be gated on
Hugging Face behind an account and a licence acceptance, and the Community
License carries revenue thresholds above which separate enterprise terms apply.

TripoSR does the same job — single image to a complete mesh with predicted
hidden geometry — under **MIT**, ungated. That makes it the engine a build can
actually be verified against, and the cleaner one to ship commercially, so it is
the default. SPAR3D remains implemented behind the same boundary for anyone who
accepts its terms; it is untested here because its weights cannot be fetched
without credentials.

Both sit behind `engines/base.py`, so a later native or Core ML engine replaces
them without touching the worker, the protocol, or the app.

## Install

```bash
cd tools/sculptor-engine
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

That runs the protocol, input-preparation and mesh layers and the whole unit
suite. It deliberately does not pull PyTorch.

To actually reconstruct:

```bash
pip install -r requirements-triposr.txt
./scripts/install_triposr.sh
```

`install_triposr.sh` clones the TripoSR runtime into `vendor/` (not committed,
matching how `tools/coreml-conversion` treats its third-party dependencies) and
applies two documented patches, both needed on Apple Silicon:

1. `tsr/utils.py` imports `rembg` at module scope but only uses it in
   `remove_background()`, which Sculptor never calls. Made lazy so the unused
   background remover does not drag `onnxruntime` into the environment.
2. `tsr/models/isosurface.py` hands the density grid straight to `torchmcubes`,
   which accepts CPU tensors only and raises `vol must be a CPU tensor` for MPS
   input — a case upstream's `AttributeError` fallback does not catch. The grid
   now always crosses to the CPU for marching cubes.

Python 3.9+ runs the core layers and the unit suite. The reconstruction backends
want 3.11+.

## Install the model

Weights live in the App Group:

```text
group.com.hakobs.imagekid/Models/Sculptor/TripoSR/v1/
├── config.yaml
└── model.ckpt          # ~1.6 GB
```

`SCULPTOR_MODELS_DIR` overrides the search root; the app passes its
sandbox-authorised container path explicitly rather than letting the worker
guess. To install them outside the app during development:

```bash
python scripts/fetch_weights.py
python -m sculptor_engine --check
```

**The app's own "Install Model" button does not work yet.** It fetches from
`https://models-data.hakobs.com/v1/TripoSR/v1/`, the same bucket ImageKid's Core
ML models come from, and nothing has been uploaded there — the URL currently
404s. Publish them once with:

```bash
R2_ENDPOINT=… R2_BUCKET=… AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=… \
  ./scripts/upload_weights_to_r2.sh TripoSR v1
```

TripoSR is MIT, which permits redistribution with its notice. SPAR3D's Community
License does not grant the same freedom — read it before mirroring those.

## Run

```bash
# One-shot, for the spike or for scripting a corpus.
python -m sculptor_engine --image temple.png --output temple-3d.glb
python -m sculptor_engine --image toy.png --output toy.glb --device cpu --low-memory

# The long-lived worker the app drives.
python -m sculptor_engine --serve
```

## Protocol

One JSON object per line, both directions. `stdout` carries protocol traffic and
nothing else; diagnostics go to `stderr`. The worker takes a private duplicate
of stdout at startup and points file descriptor 1 at stderr, so a library that
prints a banner on import cannot corrupt the stream.

Keys are camelCase so Swift decodes them with a default `JSONDecoder`.

### App → worker

```json
{"type":"generate","jobId":"j1","sourcePath":"/…/source.png","workspace":"/…/jobs/j1",
 "maskPath":"/…/mask.png","options":{"inputSize":512}}
{"type":"cancel","jobId":"j1"}
{"type":"shutdown"}
```

`cancel` is handled on the reader thread, so it reaches a running job
immediately rather than queueing behind it. Cancellation is cooperative and
lands at stage boundaries; the forward pass itself is not interruptible. For an
immediate stop the app terminates the worker, which also reclaims device memory.

Unknown option keys are rejected rather than ignored, so a typo fails loudly.

### Worker → app

```json
{"type":"ready","protocolVersion":1,"engine":"triposr","engineAvailable":true,"detail":null}
{"type":"progress","jobId":"j1","stage":"reconstructing","stageFraction":0.4,"fraction":0.32}
{"type":"result","jobId":"j1","glbPath":"…","previewPath":"…","triangleCount":200864,…}
{"type":"error","jobId":"j1","code":"modelNotInstalled","message":"…","recoverable":true}
```

Stages, in order: `preparingImage`, `isolatingObject`, `reconstructing`,
`buildingHiddenSides`, `cleaningModel`, `preparingPreview`. `fraction` is the
overall 0..1 progress. Its weights are still derived from stage ordering rather
than the measurements below; see "Still open".

No image or model bytes ever travel in a message; only paths inside the job
workspace.

## Job workspace

```text
<workspace>/
├── input/prepared.png    # square, subject-cropped engine input
├── temp/                 # staging; model.glb.part lives here
├── output/model.glb      # canonical asset
└── output/preview.ply    # viewer copy; Model I/O cannot read GLB
```

The GLB is written to `temp/`, reopened to prove it is valid, and only then
moved into `output/` with `os.replace`. A failed generation cannot leave a
half-written asset. The source image is opened read-only and never modified.

## Asset convention

Up `+Y`, origin at bottom-centre, normalised to a one-unit longest edge with
`appliedScale` reported so the engine's original dimensions stay recoverable.

**Orientation is corrected, not assumed.** Single-image reconstruction happens in
the input camera's frame, so a subject rendered from above — every isometric
Tiko Media asset — comes out tilted back by the camera's elevation.

The fix is `pitchCorrection`, in degrees. **-60°** stands up the steep isometric
dioramas that make up most of the Tiko catalogue; 0 is right for an eye-level
photo.

There is no single correct constant, even within one catalogue. `wat-pho` and
`peace-palace` are steep three-quarter views and need -60; `westminster-abbey`
is a much flatter elevation and -60 over-rotates it into a forward lean. That is
why this is a user-facing control — a three-way **Seen from** choice mapping to
0 / -30 / -60 — rather than a hardcoded value. The camera's height cannot be
recovered from the image, and getting it wrong is the single most visible defect
in the output.

`alignGround` attempts the same thing from geometry alone, by taking the
object's largest flat surface as its base. It is **off by default and not
recommended**: on real reconstructions the largest planar region is frequently
the smooth back face the engine invents rather than the base. On this corpus it
corrected the Madrid palace and laid `peace-palace` and `wat-pho` on their
sides. It is kept because the idea is sound for genuinely plated objects, but a
known camera angle beats it every time.

Normalisation works on a `trimesh.Scene` rather than one concatenated mesh,
because concatenation collapses per-geometry materials and would silently
destroy texturing.

Forward-axis inference (`-Z`) is deliberately not implemented: the doc marks it
useful but requires that an ambiguous forward direction never blocks export.

## Test

```bash
python -m pytest tests/ -q          # 89 tests, no network, no weights needed
```

The reconstruction engine is substituted with one returning real `trimesh`
geometry, so these cover the worker — staging, error classification,
cancellation, protocol hygiene — rather than the model itself.

The Swift side has matching protocol tests plus an integration test that drives
this worker over a real pipe:

```bash
cd packages/ImageKidSculptorKit
SCULPTOR_WORKER_PYTHON=$PWD/../../tools/sculptor-engine/.venv/bin/python \
SCULPTOR_WORKER_SOURCE=$PWD/../../tools/sculptor-engine \
swift test
```

## Measured on the corpus

Ten Tiko Media landmark assets (1024×1024 stylised dioramas, nine with clean
alpha), Apple M3 / 24 GB / macOS 26.5, MPS:

| Marching cubes | Inference (median) | Triangles | Peak RSS |
| --- | --- | --- | --- |
| 256 | 9.0 s (8.2–14.5) | 108k–258k | 3.5 GB |
| 384 | 30.6 s (28.2–50.2) | 245k–594k | 3.5 GB |

10/10 succeeded at both settings. 3.5 GB peak is well under the 10.5 GB the
SPAR3D documentation quotes, so the CPU-fallback advice for machines below 32 GB
does not apply to this engine.

Reproduce with:

```bash
python scripts/run_corpus.py <folder-of-images> --output out/corpus --render
```

`--render` writes a front/right/back/left/top contact sheet per asset via
`scripts/render_views.py`, a dependency-free numpy rasteriser that needs no GL
context. Rotating behind the model is the only way to judge inferred hidden
geometry, and a triangle count cannot prove it.

### Quality, honestly

**With the right `pitchCorrection`, results are good.** `wat-pho` comes out as a
legible Thai temple — tiered roof, upswept finials, a colonnade of distinct
columns. `peace-palace` is an upright building with a clock tower and an arched
facade on its base plate. Front, left and right all read correctly, and the
inferred back is plausible if soft.

Get the pitch wrong and the same mesh is an unreadable tilted slab. Orientation,
not resolution, was the difference between "unusable" and "usable" on this
corpus — which is why the app asks about the source viewpoint.

The remaining limits are real. The back face is always the softest side, since
nothing constrains it. Very intricate subjects still blur: `white-temple`'s
filigree spires merge into a mass. Fine architectural relief reads as texture on
a solid rather than as separate massing. Raising marching cubes from 256 to 384
triples time and triangles for a modest gain, because the triplane resolution —
not the isosurface — is the limit.

For the Tiko catalogue this is solidly good enough for maps, globes, game props
and background assets. A foreground hero asset would still want more.

## Still open

1. Upload the weights to R2 (`scripts/upload_weights_to_r2.sh`). Until then the
   app's in-app install fails and the model must be installed from the command
   line with `scripts/fetch_weights.py`.
2. Replace the protocol's stage weights with the measured timings above; they
   are currently derived from stage ordering, so the progress bar is uneven.
3. `engines/spar3d.py` has never been run: its weights are gated. The
   `from_pretrained`/`run_image` signatures are written from upstream docs and
   need confirming against a pinned commit before anyone relies on it.
4. Package a Python runtime into the app bundle. Until then the Sculptor target
   cannot be sandboxed, because a sandboxed process may only execute binaries it
   ships with. See `apps/native-macos/project.yml`.
5. Evaluate a higher-fidelity engine for hero assets, and a Core ML port to
   remove the Python runtime altogether.
