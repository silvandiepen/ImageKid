# Offline AI upscaling

## Objective

ImageKid should provide a useful Topaz-like enlargement workflow without Topaz, cloud APIs, subscriptions, model downloads, or online activation. All code and model weights required at runtime are bundled and execute locally.

The application must distinguish ordinary geometric resizing from machine-learning reconstruction. Standard resize is predictable interpolation. AI upscale may reconstruct textures or edges that were not present in the source.

## Feasible first implementation

### Images

Bundle a general Real-ESRGAN-family x4 model converted to Core ML. Use it for photographs, screenshots, compressed web images, and mixed content. Provide 2x and 4x output; produce 3x by running the model at its supported scale and applying deterministic high-quality reduction when necessary.

Optionally bundle a smaller illustration/anime model after verifying that the model weights, not only the source code, are redistributable under acceptable terms.

### Video

Decode a clip frame by frame, apply the same local image model to each frame, composite annotations, and write the frames into a new video while retaining timestamps and audio.

This is technically straightforward, deterministic, and fully offline. Its limitation is temporal consistency: details may change slightly between adjacent frames, causing shimmer, flicker, or unstable texture.

The product must describe this mode as **Frame Upscale**, not imply that it is temporal video restoration.

## Higher-quality temporal mode

A future **Temporal Upscale** may use BasicVSR++, BasicVSR, RealBasicVSR, or another openly licensed video super-resolution model that analyses neighbouring frames.

A candidate is accepted only when all of the following are proven:

- model code and weights can be redistributed;
- conversion to Core ML or another native local runtime is reproducible;
- all required operators work without Python or a custom unsigned runtime;
- output is temporally more stable than frame mode;
- memory stays bounded on the minimum supported Apple Silicon Mac;
- long clips can be processed in temporal windows without visible boundary artifacts;
- cancellation, progress, audio synchronisation, and timestamps remain correct;
- app size and processing time are acceptable.

BasicVSR++ is not assumed to be easy to ship. Optical flow, deformable alignment, recurrent state, and dynamic temporal shapes may require graph changes or custom Metal implementation. It is a research and benchmarking track, not a first-release promise.

## Runtime choice

### Preferred: Core ML

Reasons:

- executes entirely on device;
- can use CPU, GPU, and Neural Engine where compatible;
- integrates with Swift and Xcode;
- can compile bundled model packages during the build;
- avoids embedding Python and PyTorch;
- supports model configuration and compute-unit selection.

### Rejected for the first implementation

- **Topaz SDK or application automation:** proprietary, paid, and outside the offline/open-source requirement.
- **Cloud inference:** violates privacy, offline operation, and zero-running-cost requirements.
- **Bundled Python/PyTorch:** very large distribution, complex signing, slow startup, dependency risk, and poor native integration.
- **Shelling out to a separately installed executable:** unreliable and not self-contained.
- **Runtime model downloads:** violates the requirement that the installed app works permanently offline.

A native open-source inference library may be reconsidered only if Core ML cannot execute the selected model and the library has clear redistribution terms, macOS support, reproducible builds, and acceptable signing and app-size consequences.

## Model package

Each included model has a manifest:

```json
{
  "id": "general-x4-v1",
  "displayName": "General",
  "version": "1.0.0",
  "architecture": "Real-ESRGAN compatible",
  "nativeScale": 4,
  "inputChannels": 3,
  "supportsAlpha": false,
  "source": "upstream repository and release URL",
  "sourceCommit": "pinned commit",
  "sourceChecksum": "sha256",
  "convertedChecksum": "sha256",
  "license": "verified licence identifier",
  "conversionToolchain": "coremltools version and script revision",
  "attribution": "required notice"
}
```

Model conversion scripts belong in the repository, even if converted weights are stored through release assets or large-file storage later. A release must be reproducible from the documented source checkpoint.

## Alpha handling

Most RGB upscalers do not process alpha safely.

For transparent images:

1. unpremultiply colour where required;
2. upscale RGB using the model;
3. upscale alpha independently using a deterministic high-quality method;
4. optionally use an edge-aware alpha path after testing;
5. recombine and premultiply correctly for rendering or export.

The result must be tested for dark fringes and colour bleeding around transparent edges.

## Tiling

The engine must support overlapping tiles because large media can exceed memory.

Requirements:

- model-specific input alignment;
- reflection or edge padding;
- overlap large enough to cover the receptive field;
- deterministic valid-region crop or feather blending;
- tile order independent output;
- adaptive tile size based on memory pressure;
- bounded concurrent tiles;
- cancellation between tiles;
- progress based on completed weighted tile area.

A debug mode should visualise tile boundaries and difference maps during development.

## Image preview

Full-image inference may be slow. The sheet should create a fast preview from a selected or representative region.

- Default region is centred around visible detail.
- User may drag the preview region.
- A before/after divider compares standard resize and AI output.
- Preview uses the same model and colour pipeline as export.
- Preview quality must not imply that the entire image is already processed.

## Video pipeline

1. Open a non-protected `AVAsset`.
2. Determine transformed dimensions, colour metadata, duration, frame timing, audio tracks, and output requirements.
3. Configure `AVAssetReader` for decoded pixel buffers.
4. Configure `AVAssetWriter` and its pixel-buffer adaptor for output dimensions and codec.
5. For each video sample:
   - respect backpressure;
   - convert pixel format and colour representation;
   - apply crop;
   - run tiled inference;
   - apply final target resize if needed;
   - render effects and annotations active at the sample timestamp;
   - append with the original or deliberately transformed presentation timestamp.
6. Pass through or locally re-encode audio.
7. Finalise atomically.

The pipeline should not export intermediate PNG frames under normal operation.

## Temporal windowing research

A temporal model may require past and future frames. The research implementation should define:

- number of frames per window;
- overlap between windows;
- recurrent state handoff;
- scene-cut detection;
- beginning and end padding;
- variable-frame-rate handling;
- cancellation boundaries;
- output ordering;
- memory budget.

Scene cuts must reset temporal state to prevent ghosting across unrelated shots.

## Quality modes

Keep the product choices understandable:

### Standard Resize

Fast, deterministic interpolation. No generated detail.

### AI General

For photographs, screenshots, and mixed content. Reconstructs edges and texture.

### AI Illustration

For flat artwork, icons, animation, and line work. Included only after licence verification.

### Temporal Video

Future high-quality video-only mode. Hidden until production-ready.

Do not expose raw model names as the primary UI labels, though model and licence details remain available in About or Model Information.

## Performance expectations

No universal speed promise should be made. Processing depends on input dimensions, output scale, model, tile size, clip length, codec, and Mac generation.

Development benchmarks must record:

- hardware and memory;
- macOS version;
- model version and compute units;
- input/output dimensions;
- tile size and overlap;
- frames per second or seconds per image;
- peak memory;
- output quality metrics and visual review.

The application may offer a lower-memory mode but must not secretly change models or quality without telling the user.

## Model selection criteria

A model must score acceptably across:

- photographs;
- screenshots and UI text;
- pixel art and icons;
- illustrations;
- compressed images;
- faces without dedicated face hallucination;
- transparent-edge cases;
- adjacent video-frame stability;
- colour and luminance preservation;
- tile seams;
- model size;
- Apple Silicon speed and memory.

A model that produces attractive but inaccurate faces, text, or UI details should not be the only default.

## Licensing policy

“Open source” code does not automatically prove that pretrained weights may be redistributed. Before bundling any artifact:

1. record the code licence;
2. locate explicit model-weight terms;
3. verify commercial redistribution if the app may be sold;
4. retain copyright notices;
5. include attribution and licence text;
6. pin the exact checkpoint and checksum;
7. avoid datasets or weights with unclear downstream restrictions;
8. document any conversion modifications.

If weight terms remain ambiguous, do not bundle that checkpoint. Train or obtain a checkpoint with explicit rights, or choose another model.

## User trust

The UI must state:

- processing happens locally;
- no media is uploaded;
- AI upscaling may create plausible detail;
- frame mode may flicker in video;
- processing can be slow and power intensive;
- the source is preserved.

The app should include a model information view listing the exact bundled models, licences, versions, and upstream projects.