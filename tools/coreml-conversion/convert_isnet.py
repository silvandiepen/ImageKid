#!/usr/bin/env python3
"""Convert ISNet general-use to a Core ML .mlpackage.

Converts the published ``isnet-general-use.onnx`` graph (the same artefact the
macOS app downloads for its rembg-based Best Quality engine) into a Core ML
model with an image input ``input`` (1024x1024, RGB) and a single-channel mask
output ``output``. Matches ``CoreMLBackgroundRemoverConfiguration``.

The ISNet input normalisation (scale ``1/255``, bias ``-0.5``) is baked into the
image input. The mask is left unnormalised; the Swift side applies the same
per-image min-max normalisation that ``rembg`` uses.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path

import torch
import torch.nn as nn

# Same artefact the macOS app references (BackgroundRemovalModelConfiguration).
ONNX_URL = "https://huggingface.co/fofr/comfyui/resolve/main/rembg/isnet-general-use.onnx"
INPUT_SIZE = 1024


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="./out/ISNet.mlpackage")
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


class MaskWrapper(nn.Module):
    """Select the primary mask from ISNet's outputs.

    ISNet emits several side outputs; the first is the full-resolution mask.
    onnx2torch may return a tensor or a tuple depending on the graph, so handle
    both.
    """

    def __init__(self, model: nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        y = self.model(x)
        if isinstance(y, (list, tuple)):
            y = y[0]
        return y


def build_torch_from_onnx(onnx_path: Path) -> nn.Module:
    from onnx2torch import convert as onnx_to_torch

    model = onnx_to_torch(str(onnx_path))
    model.eval()
    return MaskWrapper(model).eval()


def convert(args: argparse.Namespace) -> None:
    import coremltools as ct

    onnx_path = download(ONNX_URL, Path(args.cache))
    model = build_torch_from_onnx(onnx_path)

    example = torch.rand(1, 3, args.input_size, args.input_size)
    with torch.no_grad():
        traced = torch.jit.trace(model, example)

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="input",
                shape=(1, 3, args.input_size, args.input_size),
                # ISNet expects (pixel/255 - 0.5) with unit std.
                scale=1 / 255.0,
                bias=[-0.5, -0.5, -0.5],
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="output")],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
    )

    mlmodel.short_description = "ISNet general-use background mask for ImageKid"
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output))
    print(f"Wrote {output}")


if __name__ == "__main__":
    convert(parse_args())
