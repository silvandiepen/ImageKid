"""Pure-PyTorch deformable convolution (DCNv2) using grid_sample.

`torchvision.ops.deform_conv2d` is a fused C++ op that neither ONNX nor Core ML
can represent. This reimplements the same computation with `grid_sample` +
matmul — ops that both toolchains support — so BiRefNet (which uses deformable
convolution in its ASPP decoder) can be converted to Core ML.

Apply `patch()` BEFORE the BiRefNet remote code is imported so its
`from torchvision.ops import deform_conv2d` binds to this implementation.
"""
from __future__ import annotations

import torch
import torch.nn.functional as F


def _pair(x):
    return tuple(x) if isinstance(x, (list, tuple)) else (x, x)


def deform_conv2d_grid_sample(
    input, offset, weight, bias=None,
    stride=(1, 1), padding=(0, 0), dilation=(1, 1), mask=None,
):
    stride, padding, dilation = _pair(stride), _pair(padding), _pair(dilation)
    B, C_in, H_in, W_in = input.shape
    C_out, C_in_g, kh, kw = weight.shape
    groups = C_in // C_in_g
    if groups != 1:
        raise NotImplementedError("grid_sample deform conv supports groups==1 only")
    sh, sw = stride
    ph, pw = padding
    dh, dw = dilation
    n_taps = kh * kw

    H_out = (H_in + 2 * ph - dh * (kh - 1) - 1) // sh + 1
    W_out = (W_in + 2 * pw - dw * (kw - 1) - 1) // sw + 1
    og = offset.shape[1] // (2 * n_taps)  # offset groups
    C_per = C_in // og

    x = F.pad(input, (pw, pw, ph, ph))
    Hp, Wp = x.shape[2], x.shape[3]
    dtype, device = input.dtype, input.device

    # Base sampling coordinates (padded space) per tap. Index offset/mask channels
    # directly (rather than a 6D reshape) so every intermediate stays rank <= 5,
    # which Core ML requires.
    oy = torch.arange(H_out, dtype=dtype, device=device) * sh
    ox = torch.arange(W_out, dtype=dtype, device=device) * sw
    ay = (torch.arange(kh, dtype=dtype, device=device) * dh).repeat_interleave(kw)  # (n_taps,)
    ax = (torch.arange(kw, dtype=dtype, device=device) * dw).repeat(kh)             # (n_taps,)

    taps = []
    for t in range(n_taps):
        by = oy[None, :, None] + ay[t]  # (1,H_out,1)
        bx = ox[None, None, :] + ax[t]  # (1,1,W_out)
        parts = []
        for g in range(og):
            ch = (g * n_taps + t) * 2  # torchvision offset layout: [group, tap, (y,x)]
            gy = by + offset[:, ch + 0]      # (B,H_out,W_out)
            gx = bx + offset[:, ch + 1]
            gyn = 2.0 * gy / (Hp - 1) - 1.0
            gxn = 2.0 * gx / (Wp - 1) - 1.0
            grid = torch.stack([gxn, gyn], dim=-1)  # (B,H_out,W_out,2)
            xin = x[:, g * C_per:(g + 1) * C_per]
            s = F.grid_sample(
                xin, grid, mode="bilinear", padding_mode="zeros", align_corners=True
            )
            if mask is not None:
                s = s * mask[:, g * n_taps + t:g * n_taps + t + 1]
            parts.append(s)
        taps.append(torch.cat(parts, dim=1))  # (B,C_in,H_out,W_out)

    cols = torch.stack(taps, dim=2).reshape(B, C_in * n_taps, H_out * W_out)
    w = weight.reshape(C_out, C_in * n_taps)
    out = torch.matmul(w, cols).reshape(B, C_out, H_out, W_out)
    if bias is not None:
        out = out + bias.view(1, C_out, 1, 1)
    return out


def _window_partition_le5(x, window_size):
    """Swin window partition without a rank-6 tensor (Core ML caps rank at 5).

    Same element ordering as the original 6D view/permute, done as two ≤5D steps.
    """
    ws = window_size
    B, H, W, C = x.shape
    x = x.reshape(B * (H // ws), ws, W, C)
    x = x.reshape(B * (H // ws), ws, W // ws, ws, C)
    x = x.permute(0, 2, 1, 3, 4).contiguous()
    return x.reshape(-1, ws, ws, C)


def _window_reverse_le5(windows, window_size, H, W):
    ws = window_size
    C = windows.shape[-1]
    B = windows.shape[0] // ((H // ws) * (W // ws))
    x = windows.reshape(B * (H // ws), W // ws, ws, ws, C)
    x = x.permute(0, 2, 1, 3, 4).contiguous()
    x = x.reshape(B * (H // ws), ws, W, C)
    return x.reshape(B, H, W, C)


def patch_coremltools_numpy2() -> None:
    """Fix coremltools' `_cast` for numpy 2.x.

    coremltools does `int(x.val)` on a shape-(1,) array constant; numpy 2.x raises
    "only 0-dimensional arrays can be converted to Python scalars" (numpy 1.x
    allowed it). Scalarize the value first. This unblocks the mature jit.trace
    frontend for the Swin backbone's int casts.
    """
    import numpy as np
    import coremltools.converters.mil.frontend.torch.ops as ops

    if getattr(ops, "_imagekid_cast_patched", False):
        return
    mb = ops.mb
    _get_inputs = ops._get_inputs

    def _cast(context, node, dtype, dtype_name):
        inputs = _get_inputs(context, node, expected=1)
        x = inputs[0]
        if not (len(x.shape) == 0 or np.all([d == 1 for d in x.shape])):
            raise ValueError("input to cast must be either a scalar or a length 1 tensor")
        if x.can_be_folded_to_const():
            if not isinstance(x.val, dtype):
                val = x.val
                if isinstance(val, np.ndarray):
                    val = val.reshape(-1)[0].item()  # numpy-2-safe scalarize
                res = mb.const(val=dtype(val), name=node.name)
            else:
                res = x
        elif len(x.shape) > 0:
            x = mb.squeeze(x=x, name=node.name + "_item")
            res = mb.cast(x=x, dtype=dtype_name, name=node.name)
        else:
            res = mb.cast(x=x, dtype=dtype_name, name=node.name)
        context.add(res, node.name)

    ops._cast = _cast
    ops._imagekid_cast_patched = True
    print("Patched coremltools _cast for numpy 2.x")


def patch_force_contiguous() -> None:
    """Force `.contiguous()` after every permute/transpose.

    coremltools' torch.export/EXIR frontend miscompiles non-contiguous (permuted)
    tensors — it reads them with a contiguous stride assumption, scrambling Swin
    window tensors into a blocky mask. Materialising contiguous copies makes the
    exported graph carry explicit clones that coremltools handles correctly.
    """
    import torch as _t

    if getattr(_t.Tensor, "_imagekid_contig_patched", False):
        return
    _permute, _transpose = _t.Tensor.permute, _t.Tensor.transpose

    def permute(self, *dims):
        return _permute(self, *dims).contiguous()

    def transpose(self, dim0, dim1):
        return _transpose(self, dim0, dim1).contiguous()

    _t.Tensor.permute = permute
    _t.Tensor.transpose = transpose
    _t.Tensor._imagekid_contig_patched = True
    print("Patched Tensor.permute/transpose to force contiguity")


def patch_swin_windows(module) -> None:
    """Swap the BiRefNet Swin backbone's window ops for the ≤5D versions."""
    module.window_partition = _window_partition_le5
    module.window_reverse = _window_reverse_le5
    print("Patched Swin window_partition/window_reverse to rank<=5")


def register_grid_sample_onnx2torch() -> None:
    """Teach onnx2torch to convert ONNX GridSample -> torch grid_sample.

    onnx2torch has no built-in GridSample converter; without this the re-import of
    the exported BiRefNet ONNX (which now uses GridSample in place of deform conv)
    fails. coremltools converts torch grid_sample natively.
    """
    from onnx2torch.node_converters.registry import add_converter
    from onnx2torch.utils.common import OnnxToTorchModule, OperationConverterResult, onnx_mapping_from_node

    def _s(v, default):
        if v is None:
            return default
        return v.decode() if isinstance(v, bytes) else v

    class GridSample(torch.nn.Module, OnnxToTorchModule):
        def __init__(self, mode, padding_mode, align_corners):
            super().__init__()
            self.mode = mode
            self.padding_mode = padding_mode
            self.align_corners = align_corners

        def forward(self, x, grid):
            return F.grid_sample(
                x, grid, mode=self.mode,
                padding_mode=self.padding_mode, align_corners=self.align_corners,
            )

    @add_converter(operation_type="GridSample", version=16)
    def _convert(node, graph):  # noqa: ANN001
        attrs = node.attributes
        mode = _s(attrs.get("mode", "bilinear"), "bilinear")
        padding_mode = _s(attrs.get("padding_mode", "zeros"), "zeros")
        align_corners = bool(attrs.get("align_corners", 0))
        module = GridSample(mode, padding_mode, align_corners)
        return OperationConverterResult(
            torch_module=module, onnx_mapping=onnx_mapping_from_node(node)
        )

    print("Registered onnx2torch GridSample converter")


def patch() -> None:
    import torchvision.ops as ops
    import torchvision.ops.deform_conv as dc

    ops.deform_conv2d = deform_conv2d_grid_sample
    dc.deform_conv2d = deform_conv2d_grid_sample
    # torchvision's DeformConv2d module references the module-global name.
    if hasattr(dc, "DeformConv2d"):
        _orig_forward = dc.DeformConv2d.forward

        def forward(self, input, offset, mask=None):
            return deform_conv2d_grid_sample(
                input, offset, self.weight, self.bias,
                stride=self.stride, padding=self.padding,
                dilation=self.dilation, mask=mask,
            )

        dc.DeformConv2d.forward = forward
    print("Patched deform_conv2d -> grid_sample implementation")
