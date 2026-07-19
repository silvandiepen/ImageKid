#!/usr/bin/env python3
"""Convert BiRefNet (MIT-licensed) to a Core ML .mlpackage.

BiRefNet is a commercially-licensed (MIT) high-resolution dichotomous image
segmentation model — a drop-in, higher-quality replacement for the DIS5K-encumbered
ISNet used by rembg. This produces an image input `input` (1024x1024, RGB) and a
single-channel mask output `output`, matching `CoreMLBackgroundRemoverConfiguration`.

ImageNet normalisation is baked into a wrapper so the Core ML image input can be a
plain 0..1 RGB image; the Swift side applies the same min-max mask normalisation.

Default is the lightweight `BiRefNet_lite` (Swin-tiny backbone) for on-device use;
pass `--repo ZhengPeng7/BiRefNet` for the full model.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import torch
import torch.nn as nn

# BiRefNet's Swin backbone breaks coremltools' direct torch tracer (an aten::Int
# cast on a dynamic shape). Exporting to ONNX first constant-folds those shape ops
# at the fixed 1024 input, then onnx2torch -> coremltools converts cleanly (the
# same path ISNet/U2Net use).
INPUT_SIZE = 1024
IMAGENET_MEAN = [0.485, 0.456, 0.406]
IMAGENET_STD = [0.229, 0.224, 0.225]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="./out/BiRefNet.mlpackage")
    parser.add_argument("--repo", default="ZhengPeng7/BiRefNet_lite")
    parser.add_argument("--input-size", type=int, default=INPUT_SIZE)
    parser.add_argument("--cache", default="./cache")
    return parser.parse_args()


class NormalizedMask(nn.Module):
    """Bake ImageNet normalisation in and reduce BiRefNet's outputs to one mask.

    BiRefNet emits a list of supervision maps; the last is the final prediction
    (logits). We normalise the 0..1 image input and sigmoid the final map.
    """

    def __init__(self, model: nn.Module) -> None:
        super().__init__()
        self.model = model
        self.register_buffer("mean", torch.tensor(IMAGENET_MEAN).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(IMAGENET_STD).view(1, 3, 1, 1))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = (x - self.mean) / self.std
        y = self.model(x)
        if isinstance(y, (list, tuple)):
            y = y[-1]
        return torch.sigmoid(y)


def build_model(repo: str) -> nn.Module:
    # Replace the unconvertible fused deform_conv2d op before the remote BiRefNet
    # code imports it, so its decoder uses the grid_sample implementation.
    import patch_deform
    patch_deform.patch()

    from transformers import AutoModelForImageSegmentation

    model = AutoModelForImageSegmentation.from_pretrained(repo, trust_remote_code=True)
    model.eval()

    # Rewrite the Swin backbone's rank-6 window ops (Core ML caps rank at 5).
    import sys
    remote_module = sys.modules.get(type(model).__module__)
    if remote_module is not None and hasattr(remote_module, "window_partition"):
        patch_deform.patch_swin_windows(remote_module)

    return NormalizedMask(model).eval()


def convert(args: argparse.Namespace) -> None:
    import coremltools as ct
    import patch_deform

    # The EXIR frontend miscompiles this model (blocky mask); use the mature
    # jit.trace frontend, unblocked by the numpy-2 _cast fix.
    patch_deform.patch_coremltools_numpy2()
    model = build_model(args.repo)

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
        # BiRefNet trips coremltools' default fp16 const pass ("only 0-dimensional
        # arrays can be converted to Python scalars"); convert in fp32.
        compute_precision=ct.precision.FLOAT32,
    )

    mlmodel.short_description = f"BiRefNet ({args.repo}) background mask for ImageKid"
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output))
    print(f"Wrote {output}")


if __name__ == "__main__":
    convert(parse_args())
