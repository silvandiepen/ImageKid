#!/usr/bin/env python3
"""Convert Real-ESRGAN x4plus to a Core ML .mlpackage.

Produces an image-in / image-out model with feature names ``input`` and
``output`` and a native 4x scale, matching ``CoreMLUpscalerConfiguration`` in the
ImageKidInference Swift package.

By default the model uses a flexible input size so Swift can feed native tile
sizes. Pass ``--fixed-size N`` for a fixed NxN input instead (then set
``CoreMLUpscalerConfiguration.fixedInputSize`` to match).
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path

import torch
import torch.nn as nn

# Same artefact the macOS app references.
WEIGHTS_URL = (
    "https://github.com/xinntao/Real-ESRGAN/releases/download/"
    "v0.1.0/RealESRGAN_x4plus.pth"
)
NATIVE_SCALE = 4


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="./out/RealESRGAN.mlpackage")
    parser.add_argument("--cache", default="./cache")
    parser.add_argument(
        "--fixed-size",
        type=int,
        default=None,
        help="Fixed square input edge in pixels. Omit for a flexible-shape model.",
    )
    parser.add_argument("--min-size", type=int, default=64)
    parser.add_argument("--max-size", type=int, default=512)
    parser.add_argument("--trace-size", type=int, default=256)
    return parser.parse_args()


def download(url: str, cache_dir: Path) -> Path:
    import requests

    cache_dir.mkdir(parents=True, exist_ok=True)
    destination = cache_dir / os.path.basename(url)
    if destination.exists():
        return destination
    print(f"Downloading {url}")
    with requests.get(url, stream=True, timeout=120) as response:
        response.raise_for_status()
        with open(destination, "wb") as handle:
            for chunk in response.iter_content(chunk_size=1 << 20):
                handle.write(chunk)
    return destination


def build_generator(weights_path: Path) -> nn.Module:
    """Build RRDBNet and load the x4plus weights."""
    from basicsr.archs.rrdbnet_arch import RRDBNet

    model = RRDBNet(
        num_in_ch=3,
        num_out_ch=3,
        num_feat=64,
        num_block=23,
        num_grow_ch=32,
        scale=NATIVE_SCALE,
    )
    state = torch.load(weights_path, map_location="cpu")
    key = "params_ema" if "params_ema" in state else "params"
    model.load_state_dict(state[key], strict=True)
    model.eval()
    return model


class ImageIOWrapper(nn.Module):
    """Wrap the generator for Core ML image I/O.

    The Core ML ImageType input scales pixels to 0..1, so the generator receives
    0..1 RGB. Real-ESRGAN returns 0..1 RGB; scale back to 0..255 and clamp so the
    output can be emitted as an image.
    """

    def __init__(self, model: nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        y = self.model(x)
        return torch.clamp(y, 0.0, 1.0) * 255.0


def convert(args: argparse.Namespace) -> None:
    import coremltools as ct

    weights = download(WEIGHTS_URL, Path(args.cache))
    wrapped = ImageIOWrapper(build_generator(weights)).eval()

    example = torch.rand(1, 3, args.trace_size, args.trace_size)
    with torch.no_grad():
        traced = torch.jit.trace(wrapped, example)

    if args.fixed_size:
        shape = ct.Shape(shape=(1, 3, args.fixed_size, args.fixed_size))
    else:
        shape = ct.Shape(
            shape=(
                1,
                3,
                ct.RangeDimension(args.min_size, args.max_size),
                ct.RangeDimension(args.min_size, args.max_size),
            )
        )

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="input",
                shape=shape,
                scale=1 / 255.0,
                bias=[0.0, 0.0, 0.0],
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.ImageType(name="output", color_layout=ct.colorlayout.RGB)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
    )

    mlmodel.short_description = "Real-ESRGAN x4plus upscaler for ImageKid"
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output))
    print(f"Wrote {output}")


if __name__ == "__main__":
    convert(parse_args())
