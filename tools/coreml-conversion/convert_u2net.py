#!/usr/bin/env python3
"""Convert U^2-Net (Apache-2.0) to a Core ML .mlpackage.

U^2-Net (xuebinqin/U-2-Net) is an Apache-2.0 salient-object-detection model, the
most conservatively-licensed background-removal option (no DIS5K dependency). This
converts rembg's published `u2net.onnx` into a Core ML model with an image input
`input` (320x320, RGB) and a single-channel mask output `output`, matching
`CoreMLBackgroundRemoverConfiguration(inputSize: 320x320)`.

ImageNet normalisation is baked into a wrapper; the Swift side applies the same
min-max mask normalisation U^2-Net uses.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path

import torch
import torch.nn as nn

# rembg's published U^2-Net ONNX (input 1x3x320x320, ImageNet-normalised).
ONNX_URL = "https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx"
INPUT_SIZE = 320
IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD = [0.229, 0.224, 0.225]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="./out/U2Net.mlpackage")
    parser.add_argument("--cache", default="./cache")
    parser.add_argument("--input-size", type=int, default=INPUT_SIZE)
    return parser.parse_args()


def download(url: str, cache_dir: Path) -> Path:
    import requests

    cache_dir.mkdir(parents=True, exist_ok=True)
    destination = cache_dir / os.path.basename(url)
    if destination.exists():
        return destination
    print(f"Downloading {url}")
    with requests.get(url, stream=True, timeout=300) as response:
        response.raise_for_status()
        with open(destination, "wb") as handle:
            for chunk in response.iter_content(chunk_size=1 << 20):
                handle.write(chunk)
    return destination


class NormalizedMask(nn.Module):
    """Bake ImageNet normalisation in and take U^2-Net's primary (d0) output."""

    def __init__(self, model: nn.Module) -> None:
        super().__init__()
        self.model = model
        self.register_buffer("mean", torch.tensor(IMAGENET_MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(IMAGENET_STD).view(1, 3, 1, 1))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = (x - self.mean) / self.std
        y = self.model(x)
        if isinstance(y, (list, tuple)):
            y = y[0]  # d0: the full-resolution fused prediction
        return y


def build_torch_from_onnx(onnx_path: Path) -> nn.Module:
    from onnx2torch import convert as onnx_to_torch

    model = onnx_to_torch(str(onnx_path))
    model.eval()
    return NormalizedMask(model).eval()


def convert(args: argparse.Namespace) -> None:
    import coremltools as ct

    onnx_path = download(ONNX_URL, Path(args.cache))
    model = build_torch_from_onnx(onnx_path)

    example = torch.rand(1, 3, args.input_size, args.input_size)
    with torch.no_grad():
        traced = torch.jit.trace(model, example, strict=False)

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="input",
                shape=(1, 3, args.input_size, args.input_size),
                scale=1 / 255.0,
                bias=[0.0, 0.0, 0.0],
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="output")],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
    )

    mlmodel.short_description = "U^2-Net background mask for ImageKid"
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output))
    print(f"Wrote {output}")


if __name__ == "__main__":
    convert(parse_args())
