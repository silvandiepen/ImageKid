#!/usr/bin/env python3
"""Compare ISNet, BiRefNet-lite and U^2-Net background removal on one or more photos.

For each image, writes a fit montage (Original + 3 models) and a 100% native-pixel
zoom montage focused on the subject's head/edge detail. Runs the real weights in
PyTorch (no Core ML needed) — for visual quality evaluation only.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path

import numpy as np
import torch
from PIL import Image, ImageDraw, ImageFont

IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)
ISNET_MEAN = np.array([0.5, 0.5, 0.5], dtype=np.float32)
ISNET_STD = np.array([1.0, 1.0, 1.0], dtype=np.float32)
MODELS = [
    ("ISNet (rembg)", "DIS5K · non-commercial"),
    ("BiRefNet-lite", "MIT · commercial OK"),
    ("U²-Net", "Apache-2.0 · commercial OK"),
]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--images", nargs="+", required=True)
    p.add_argument("--outdir", default="./out/compare")
    p.add_argument("--cache", default="./cache")
    return p.parse_args()


def download(url: str, cache: Path) -> Path:
    import requests

    cache.mkdir(parents=True, exist_ok=True)
    dest = cache / os.path.basename(url)
    if dest.exists():
        return dest
    with requests.get(url, stream=True, timeout=300) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for chunk in r.iter_content(1 << 20):
                f.write(chunk)
    return dest


def to_mask(arr: np.ndarray) -> np.ndarray:
    arr = np.squeeze(arr).astype(np.float32)
    lo, hi = float(arr.min()), float(arr.max())
    if hi - lo > 1e-8:
        arr = (arr - lo) / (hi - lo)
    return np.clip(arr, 0.0, 1.0)


def preprocess(img: Image.Image, size: int, mean, std) -> torch.Tensor:
    r = img.convert("RGB").resize((size, size), Image.BILINEAR)
    x = np.asarray(r, dtype=np.float32) / 255.0
    x = (x - mean) / std
    return torch.from_numpy(np.transpose(x, (2, 0, 1))[None, ...]).float()


def infer(model, img, size, mean, std, take) -> np.ndarray:
    x = preprocess(img, size, mean, std)
    with torch.no_grad():
        y = model(x)
    if isinstance(y, (list, tuple)):
        y = y[take]
    if take == -1:  # BiRefNet returns logits
        y = torch.sigmoid(y)
    return to_mask(y.cpu().numpy())


def checkerboard(w: int, h: int, cell: int = 16) -> Image.Image:
    bg = Image.new("RGB", (w, h), (210, 210, 214))
    d = ImageDraw.Draw(bg)
    for y in range(0, h, cell):
        for x in range(0, w, cell):
            if ((x // cell) + (y // cell)) % 2 == 0:
                d.rectangle([x, y, x + cell, y + cell], fill=(174, 174, 178))
    return bg


def composite(img: Image.Image, mask01: np.ndarray) -> Image.Image:
    rgb = img.convert("RGB")
    m = Image.fromarray((mask01 * 255).astype(np.uint8)).resize(rgb.size, Image.BILINEAR)
    base = checkerboard(*rgb.size)
    base.paste(rgb, (0, 0), m)
    return base


def font(size: int):
    for path in ["/System/Library/Fonts/Helvetica.ttc", "/Library/Fonts/Arial.ttf"]:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                pass
    return ImageFont.load_default()


def labelled(img: Image.Image, title: str, subtitle: str, cell_w: int, img_h: int,
             label_h: int, fit: bool) -> Image.Image:
    if fit:
        scale = min(cell_w / img.width, img_h / img.height)
        disp = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
    else:
        disp = img  # native pixels
    canvas = Image.new("RGB", (cell_w, img_h + label_h), (28, 28, 30))
    canvas.paste(disp, ((cell_w - disp.width) // 2, (img_h - disp.height) // 2))
    d = ImageDraw.Draw(canvas)
    d.rectangle([0, img_h, cell_w, img_h + label_h], fill=(40, 40, 46))
    d.text((16, img_h + 8), title, font=font(22), fill=(255, 255, 255))
    d.text((16, img_h + 33), subtitle, font=font(15), fill=(168, 172, 180))
    return canvas


def grid(cells, cols, cell_w, cell_h, pad) -> Image.Image:
    rows = (len(cells) + cols - 1) // cols
    W = pad + cols * cell_w + (cols - 1) * pad + pad
    H = pad + rows * cell_h + (rows - 1) * pad + pad
    montage = Image.new("RGB", (W, H), (18, 18, 20))
    for i, c in enumerate(cells):
        col, row = i % cols, i // cols
        montage.paste(c, (pad + col * (cell_w + pad), pad + row * (cell_h + pad)))
    return montage


def head_crop_box(mask01: np.ndarray, W: int, H: int) -> tuple[int, int, int]:
    """A square native crop over the top (head/hair) of the subject."""
    m = Image.fromarray((mask01 * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR)
    a = np.asarray(m) > 96
    ys, xs = np.where(a)
    if len(xs) == 0:
        side = min(W, H) // 2
        return (W - side) // 2, 0, side
    x0, x1, y0 = xs.min(), xs.max(), ys.min()
    sub_w = x1 - x0
    cx = (x0 + x1) // 2
    side = int(min(max(sub_w * 0.75, 360), 760, W, H))
    left = int(min(max(cx - side // 2, 0), W - side))
    top = int(min(max(y0 - side * 0.06, 0), H - side))
    return left, top, side


def main() -> None:
    args = parse_args()
    cache = Path(args.cache)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    from onnx2torch import convert as onnx_to_torch
    from transformers import AutoModelForImageSegmentation

    print("Loading models…")
    isnet = onnx_to_torch(str(download(
        "https://huggingface.co/fofr/comfyui/resolve/main/rembg/isnet-general-use.onnx", cache))).eval()
    u2net = onnx_to_torch(str(download(
        "https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx", cache))).eval()
    biref = AutoModelForImageSegmentation.from_pretrained(
        "ZhengPeng7/BiRefNet_lite", trust_remote_code=True).eval()

    for path in args.images:
        name = Path(path).stem
        img = Image.open(path).convert("RGB")
        print(f"[{name}] running 3 models on {img.width}x{img.height}…")
        masks = {
            "ISNet (rembg)": infer(isnet, img, 1024, ISNET_MEAN, ISNET_STD, 0),
            "BiRefNet-lite": infer(biref, img, 1024, IMAGENET_MEAN, IMAGENET_STD, -1),
            "U²-Net": infer(u2net, img, 320, IMAGENET_MEAN, IMAGENET_STD, 0),
        }
        cutouts = {k: composite(img, v) for k, v in masks.items()}

        # Fit montage: Original + 3 models, 2x2.
        cell_w, img_h, label_h, pad = 560, 470, 54, 28
        fit_cells = [labelled(img, "Original", f"{img.width}×{img.height}", cell_w, img_h, label_h, True)]
        for title, sub in MODELS:
            fit_cells.append(labelled(cutouts[title], title, sub, cell_w, img_h, label_h, True))
        grid(fit_cells, 2, cell_w, img_h + label_h, pad).save(outdir / f"{name}_compare.png")

        # 100% zoom montage: native-pixel crop over the head/edge detail, 1x4.
        left, top, side = head_crop_box(masks["BiRefNet-lite"], img.width, img.height)
        box = (left, top, left + side, top + side)
        zoom_label_h = 46
        zoom_cells = [labelled(img.crop(box), "Original (100%)", f"{side}×{side}px crop",
                               side, side, zoom_label_h, False)]
        for title, sub in MODELS:
            zoom_cells.append(labelled(cutouts[title].crop(box), title, sub, side, side, zoom_label_h, False))
        grid(zoom_cells, 4, side, side + zoom_label_h, pad).save(outdir / f"{name}_zoom.png")
        print(f"[{name}] wrote {name}_compare.png and {name}_zoom.png (zoom crop {side}px)")


if __name__ == "__main__":
    main()
