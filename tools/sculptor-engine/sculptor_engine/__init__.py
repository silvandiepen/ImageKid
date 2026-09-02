"""Local single-image-to-3D reconstruction worker for ImageKid Sculptor.

The worker owns reconstruction only. It never downloads anything: the Sculptor
app downloads model weights into the shared App Group, exactly as ImageKid
already does for the Best Cutout and Best Upscale Core ML models, and the worker
reports ``modelNotInstalled`` when they are absent.

See ``docs/sculptor.md`` for the product plan this implements.
"""

__all__ = ["__version__"]

__version__ = "0.1.0"
