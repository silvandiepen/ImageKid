#!/usr/bin/env python3
"""Convert fal/AuraSR-v2 (GigaGAN-based 4x super-resolution) to a Core ML
.mlpackage.

Produces an image-in / image-out model with feature names ``input`` and
``output`` and a native 4x scale (fixed 256x256 input -> 1024x1024 output),
matching ``CoreMLUpscalerConfiguration(fixedInputSize: 256)`` in the
ImageKidInference Swift package. The Swift tiler already feeds 256x256 tiles for
Real-ESRGAN, so AuraSR drops into the same engine.

AuraSR's generator takes two inputs: the low-res tile and a 128-dim latent
`noise`. We bake a fixed noise vector into the traced graph so the Core ML model
stays single-image-input (deterministic output), like every other engine.

License: AuraSR-v2 is Apache-2.0.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch
import torch.nn as nn

MODEL_ID = "fal/AuraSR-v2"
NATIVE_SCALE = 4
# AuraSR-v2 upscales 64x64 tiles to 256x256 (config: input_image_size=64,
# image_size=256). The Swift CoreMLUpscaler config must use fixedInputSize 64.
INPUT_SIZE = 64
NOISE_DIM = 128


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="./out/AuraSR.mlpackage")
    parser.add_argument("--seed", type=int, default=0, help="Seed for the baked noise latent.")
    return parser.parse_args()


def patch_aura_sr() -> None:
    """Make AuraSR traceable.

    `get_same_padding(size, …)` derives conv padding from the spatial size. Under
    `torch.jit.trace` that size is a traced tensor, so the padding becomes a 0-d
    tensor and `F.conv2d(padding=…)` fails with `padding=[]`. Since the model is
    fixed-shape, resolve the size to a concrete int so padding is a constant.
    """
    import aura_sr

    def get_same_padding(size, kernel, dilation, stride):
        if torch.is_tensor(size):
            size = int(size)
        return ((size - 1) * (stride - 1) + dilation * (kernel - 1)) // 2

    aura_sr.get_same_padding = get_same_padding


def load_upsampler() -> nn.Module:
    """Load AuraSR-v2 on CPU (from_pretrained hardcodes a CUDA device)."""
    from aura_sr import AuraSR
    from huggingface_hub import snapshot_download
    from safetensors.torch import load_file

    model_path = Path(snapshot_download(MODEL_ID))
    config = json.loads((model_path / "config.json").read_text())
    aura = AuraSR(config, device="cpu")
    checkpoint = load_file(model_path / "model.safetensors")
    aura.upsampler.load_state_dict(checkpoint, strict=True)
    return aura.upsampler.eval()


class ImageIOWrapper(nn.Module):
    """Wrap the generator for Core ML image I/O with a baked noise latent.

    The Core ML ImageType input scales pixels to 0..1, so the generator receives
    0..1 RGB. AuraSR returns 0..1 RGB; scale to 0..255 and clamp so the output
    can be emitted as an image.
    """

    def __init__(self, upsampler: nn.Module, noise: torch.Tensor) -> None:
        super().__init__()
        self.upsampler = upsampler
        self.register_buffer("noise", noise)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        y = self.upsampler(lowres_image=x, noise=self.noise)
        return torch.clamp(y, 0.0, 1.0) * 255.0


def convert(args: argparse.Namespace) -> None:
    import coremltools as ct
    import patch_deform

    # Same numpy-2.x `_cast` fix BiRefNet needs (int() of a length-1 array).
    patch_deform.patch_coremltools_numpy2()
    patch_aura_sr()
    torch.manual_seed(args.seed)
    noise = torch.randn(1, NOISE_DIM)
    wrapped = ImageIOWrapper(load_upsampler(), noise).eval()

    example = torch.rand(1, 3, INPUT_SIZE, INPUT_SIZE)
    with torch.no_grad():
        # Sanity: the wrapped model must run before we trace it.
        out = wrapped(example)
        assert out.shape == (1, 3, INPUT_SIZE * NATIVE_SCALE, INPUT_SIZE * NATIVE_SCALE), out.shape
        traced = torch.jit.trace(wrapped, example)

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="input",
                shape=ct.Shape(shape=(1, 3, INPUT_SIZE, INPUT_SIZE)),
                scale=1 / 255.0,
                bias=[0.0, 0.0, 0.0],
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.ImageType(name="output", color_layout=ct.colorlayout.RGB)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
    )

    # 8-bit linear weight quantization: ~390 MB fp16 -> ~196 MB, visually
    # lossless here, and keeps the download (and single-shot R2 upload) small.
    import numpy as np
    import coremltools.optimize.coreml as cto

    quant_config = cto.OptimizationConfig(
        global_config=cto.OpLinearQuantizerConfig(
            mode="linear_symmetric", dtype=np.int8, weight_threshold=512
        )
    )
    mlmodel = cto.linear_quantize_weights(mlmodel, quant_config)

    mlmodel.short_description = "AuraSR-v2 (GigaGAN) 4x quality upscaler for ImageKid"
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output))
    print(f"Wrote {output}")


if __name__ == "__main__":
    convert(parse_args())
