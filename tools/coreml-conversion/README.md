# Core ML conversion tooling

Reproducible scripts that convert the published Real-ESRGAN and ISNet weights
into Core ML `.mlpackage` models for the `ImageKidInference` package. The models
themselves are **not** committed to the repository — run these scripts to
produce them.

Run on a workstation (macOS or Linux) with Python 3.11+. Conversion produces the
`.mlpackage`; **running** a converted model to verify it needs macOS with the
Core ML runtime.

## Install

```bash
cd tools/coreml-conversion
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

## Convert

```bash
# Real-ESRGAN x4plus -> RealESRGAN.mlpackage (fixed 256x256 image in/out, 4x).
# The Swift tiler resizes each tile to 256; CoreMLUpscalerConfiguration.fixedInputSize matches.
python convert_realesrgan.py --output ./out/RealESRGAN.mlpackage --fixed-size 256

# AuraSR-v2 (GigaGAN) -> AuraSR.mlpackage (fixed 64x64 image in -> 256x256 out, 4x).
# Higher-quality photo detail than Real-ESRGAN. int8-quantized to ~196 MB
# (visually lossless, fits a single-shot R2 upload). A fixed noise latent is baked
# in so the Core ML model stays single-image-input. Set
# CoreMLUpscalerConfiguration(fixedInputSize: 64) on the Swift side. Apache-2.0.
python convert_aurasr.py --output ./out/AuraSR.mlpackage

# BiRefNet-lite -> BiRefNet.mlpackage (MIT, best-quality background, 1024x1024 in, mask out).
python convert_birefnet.py --output ./out/BiRefNet.mlpackage

# U^2-Net -> U2Net.mlpackage (Apache-2.0, lighter background, 320x320 in, mask out).
python convert_u2net.py --output ./out/U2Net.mlpackage

# ISNet general-use (rembg) -> ISNet.mlpackage. NOT shipped: DIS5K dataset is
# non-commercial. Kept only for reference/comparison.
python convert_isnet.py --output ./out/ISNet.mlpackage
```

Scripts download source weights on first run and cache them under `./cache`.

## Upload to R2

Models are served from `https://models-data.hakobs.com/v1/<Name>/…`. Upload a
converted package (its three files) with the helper, given Cloudflare R2
S3-compatible credentials:

```bash
R2_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com \
R2_BUCKET=<bucket> AWS_ACCESS_KEY_ID=<key> AWS_SECRET_ACCESS_KEY=<secret> \
  ./upload_model_to_r2.sh ./out/AuraSR.mlpackage AuraSR
```

This writes `v1/AuraSR/{Manifest.json, model.mlmodel, weight.bin}` — exactly what
`ModelDownloader` fetches.

### AuraSR notes

AuraSR-v2 is GigaGAN-based. `convert_aurasr.py` bakes a fixed 128-dim noise latent
into the traced graph (so the Core ML model is single-image-input and
deterministic), monkeypatches `get_same_padding` to resolve the traced spatial
size to a constant int (fixed-shape model), and reuses
`patch_deform.patch_coremltools_numpy2()` for the numpy-2.x `_cast` fix. It
converts through `jit.trace`. The `_check_trace` mismatch warning is expected —
it comes from the GAN's internal per-layer noise re-rolling in eager mode; the
fixed-noise Core ML output is a valid, stable upscale.

### BiRefNet notes (the hard one)

BiRefNet uses **deformable convolution** and a **Swin** backbone, neither of which
Core ML supports out of the box. `convert_birefnet.py` works around this via
`patch_deform.py`, which, before conversion:

- reimplements `torchvision.ops.deform_conv2d` with `grid_sample` (Core ML has no
  deform-conv op), verified numerically identical to torchvision;
- rewrites Swin's rank-6 window partition/reverse to rank ≤ 5 (Core ML caps rank at 5);
- fixes coremltools' `_cast` for numpy 2.x (`int()` of a length-1 array).

It converts through the mature `jit.trace` frontend (the `torch.export`/EXIR
frontend miscompiles this graph).

> **BiRefNet must run on the CPU (`computeUnits = .cpuOnly`).** On the Neural
> Engine or GPU it runs in fp16 and overflows on high-activation regions,
> returning NaNs that wipe the mask. The iOS app sets this for BiRefNet only;
> U²-Net and Real-ESRGAN are plain CNNs and stay on the fast default path.

### Comparing models

`compare_models.py` runs ISNet / BiRefNet / U²-Net on one or more photos and
writes a labelled montage plus a 100% zoom crop, for visual quality evaluation.

## Contract with the Swift package

The feature names and sizes below must stay in sync with the Swift
configurations. Change them in one place and mirror the change in the other.

| Model | Input feature | Output feature | Notes |
| --- | --- | --- | --- |
| Real-ESRGAN | `input` (image, RGB) | `output` (image, RGB) | Native 4x. Flexible H/W by default; pass `--fixed-size N` for a fixed-shape model and set `CoreMLUpscalerConfiguration.fixedInputSize`. |
| AuraSR-v2 | `input` (image, RGB, 64x64) | `output` (image, RGB, 256x256) | GigaGAN, native 4x. Fixed 64x64 input; set `CoreMLUpscalerConfiguration(fixedInputSize: 64, tileSize: 64)`. Baked fixed noise latent. |
| ISNet | `input` (image, RGB, 1024x1024) | `output` (multi-array mask) | Input normalisation (scale `1/255`, bias `-0.5`) is baked in. The Swift side applies the same min-max mask normalisation as `rembg`. |

Defaults match `CoreMLUpscalerConfiguration()` and
`CoreMLBackgroundRemoverConfiguration()`.

## Caveats

- Flexible-shape image models can trip on some ops; if Real-ESRGAN conversion
  fails, fall back to `--fixed-size 256` and feed fixed tiles from Swift.
- These are conversion references. Validate the output on a Mac: load each
  `.mlpackage` in Xcode, confirm the input/output feature names and types, and
  compare a few results against the current `ncnn-vulkan` / `rembg` output
  before shipping.
- Deployment target is iOS 17 / macOS 14 to match the app.
