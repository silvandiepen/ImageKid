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
# Real-ESRGAN x4plus -> RealESRGAN.mlpackage (flexible input, image in/out, 4x)
python convert_realesrgan.py --output ./out/RealESRGAN.mlpackage

# ISNet general-use -> ISNet.mlpackage (1024x1024 image in, mask multi-array out)
python convert_isnet.py --output ./out/ISNet.mlpackage
```

Both scripts download the source weights on first run (Real-ESRGAN from the
project's GitHub release, ISNet from Hugging Face — the same artefacts the macOS
app downloads today) and cache them under `./cache`.

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
