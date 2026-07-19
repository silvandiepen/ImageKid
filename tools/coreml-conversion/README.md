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

# BiRefNet-lite -> BiRefNet.mlpackage (MIT, best-quality background, 1024x1024 in, mask out).
python convert_birefnet.py --output ./out/BiRefNet.mlpackage

# U^2-Net -> U2Net.mlpackage (Apache-2.0, lighter background, 320x320 in, mask out).
python convert_u2net.py --output ./out/U2Net.mlpackage

# ISNet general-use (rembg) -> ISNet.mlpackage. NOT shipped: DIS5K dataset is
# non-commercial. Kept only for reference/comparison.
python convert_isnet.py --output ./out/ISNet.mlpackage
```

Scripts download source weights on first run and cache them under `./cache`.

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
