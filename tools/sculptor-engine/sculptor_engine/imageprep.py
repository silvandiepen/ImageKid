"""Source image normalisation, ahead of reconstruction.

Implements the "Input preparation" sequence from ``docs/sculptor.md``: decode
orientation, move to a predictable colour space, isolate the subject, crop with
consistent padding, and render the square input the engine expects.

The app owns this behaviour so that swapping the reconstruction engine does not
change user-visible import behaviour. The source file is opened read-only and
never written back.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from pathlib import Path

from PIL import Image, ImageCms, ImageOps, UnidentifiedImageError

#: Formats the worker will decode. HEIC/WebP arrive already decoded by the app
#: where the system image stack supports them, but Pillow handles WebP directly.
SUPPORTED_FORMATS = frozenset({"PNG", "JPEG", "WEBP", "TIFF", "BMP"})

#: Alpha below this counts as background when deriving a subject bounding box.
ALPHA_THRESHOLD = 8

#: An alpha channel is only treated as a real cutout if at least this fraction of
#: pixels are transparent. Fully-opaque alpha carries no subject information.
MIN_TRANSPARENT_FRACTION = 0.02


class ImagePrepError(Exception):
    """Base class for preparation failures."""


class UnsupportedImage(ImagePrepError):
    """The file decoded, but is not a format the worker accepts."""


class CorruptImage(ImagePrepError):
    """The file could not be decoded at all."""


class NoForegroundFound(ImagePrepError):
    """A mask was supplied or derived, but it selected nothing usable."""


class Suitability(str, Enum):
    """How well a source image matches Sculptor's single-object promise."""

    GOOD = "good"
    OKAY = "okay"
    POOR = "poor"


@dataclass(frozen=True)
class PreparedImage:
    """Result of preparation, plus what the app needs to explain it."""

    path: Path
    size: int
    suitability: Suitability
    #: Human-readable reasons behind a non-``GOOD`` verdict.
    notes: tuple[str, ...]
    #: Whether a real foreground mask was available (supplied or from alpha).
    had_mask: bool
    #: Fraction of the padded square the subject occupies.
    subject_coverage: float
    #: True when the subject touches the source frame edge, i.e. likely cropped.
    touches_edge: bool


def load_source(path: str | Path) -> Image.Image:
    """Open the source image, honour EXIF orientation, convert to sRGB RGBA.

    Never mutates the file on disk.
    """

    source = Path(path)
    if not source.is_file():
        raise CorruptImage(f"no readable file at {source}")

    try:
        with Image.open(source) as opened:
            image_format = opened.format
            if image_format is not None and image_format not in SUPPORTED_FORMATS:
                raise UnsupportedImage(f"unsupported image format: {image_format}")
            opened.load()
            image = opened.copy()
            icc_profile = opened.info.get("icc_profile")
    except UnidentifiedImageError as exc:
        raise CorruptImage(f"could not decode {source.name}") from exc
    except OSError as exc:
        raise CorruptImage(f"could not read {source.name}: {exc}") from exc

    image = ImageOps.exif_transpose(image)
    image = _to_srgb(image, icc_profile)
    return image.convert("RGBA")


def _to_srgb(image: Image.Image, icc_profile: bytes | None) -> Image.Image:
    """Convert a tagged image into sRGB; assume sRGB when untagged.

    A wrong-but-consistent colour space is better than a failed generation, so a
    conversion failure falls through to the original pixels.
    """

    if not icc_profile:
        return image
    try:
        from io import BytesIO

        source_profile = ImageCms.ImageCmsProfile(BytesIO(icc_profile))
        target_profile = ImageCms.createProfile("sRGB")
        mode = "RGBA" if "A" in image.getbands() else "RGB"
        return ImageCms.profileToProfile(
            image, source_profile, target_profile, outputMode=mode
        )
    except (ImageCms.PyCMSError, OSError, ValueError):
        return image


def resolve_mask(image: Image.Image, mask_path: str | Path | None) -> Image.Image | None:
    """Pick the foreground mask: an app-supplied one, else a usable alpha channel.

    Returns ``None`` when neither is available, which is not an error — the doc
    asks that generation continue rather than forcing manual masking in V1.
    """

    if mask_path is not None:
        mask = Path(mask_path)
        if not mask.is_file():
            raise NoForegroundFound(f"mask file missing at {mask}")
        try:
            with Image.open(mask) as opened:
                opened.load()
                supplied = opened.convert("L")
        except (UnidentifiedImageError, OSError) as exc:
            raise NoForegroundFound(f"could not decode mask {mask.name}") from exc
        if supplied.size != image.size:
            supplied = supplied.resize(image.size, Image.Resampling.BILINEAR)
        if not _mask_selects_anything(supplied):
            raise NoForegroundFound("supplied mask selects no pixels")
        return supplied

    alpha = image.getchannel("A")
    if _alpha_is_a_cutout(alpha):
        return alpha
    return None


def _mask_selects_anything(mask: Image.Image) -> bool:
    return mask.getbbox() is not None and (mask.getextrema()[1] > ALPHA_THRESHOLD)

def _alpha_is_a_cutout(alpha: Image.Image) -> bool:
    """Whether an alpha channel carries real subject information.

    A fully opaque channel (the common case for JPEG-sourced RGBA) tells us
    nothing, so it must not be mistaken for a cutout.
    """

    minimum, maximum = alpha.getextrema()
    if maximum <= ALPHA_THRESHOLD:
        return False
    if minimum > ALPHA_THRESHOLD:
        return False
    histogram = alpha.histogram()
    transparent = sum(histogram[: ALPHA_THRESHOLD + 1])
    total = alpha.size[0] * alpha.size[1]
    return total > 0 and (transparent / total) >= MIN_TRANSPARENT_FRACTION


def subject_box(
    image: Image.Image, mask: Image.Image | None
) -> tuple[int, int, int, int]:
    """Tight bounding box of the subject, or the whole frame when unmasked."""

    if mask is None:
        return (0, 0, image.width, image.height)
    box = mask.point(lambda value: 255 if value > ALPHA_THRESHOLD else 0).getbbox()
    if box is None:
        raise NoForegroundFound("mask selects no pixels above the alpha threshold")
    return box


def bleed_colour_outward(image: Image.Image, passes: int = 8) -> Image.Image:
    """Push subject colour into the transparent pixels around it.

    A cutout's RGB is undefined wherever alpha is zero, and exporters often
    leave it black or white there. The engine composites the subject onto a flat
    background, so those undefined pixels blend into the silhouette and leave a
    fringe — a dark or bright halo that reconstructs as a thin shell of geometry
    around the object.

    Growing the subject's own colour outward first means the composite blends
    subject into subject at the edge, and the fringe never forms. Alpha is
    untouched, so the silhouette itself does not change.
    """

    if passes <= 0:
        return image

    from PIL import ImageFilter

    rgb = image.convert("RGB")
    alpha = image.getchannel("A")
    # Anything not solidly opaque is a candidate to be filled from its
    # neighbours, which includes the soft edge itself.
    solid = alpha.point(lambda value: 255 if value > 250 else 0)

    for _ in range(passes):
        # MaxFilter spreads the nearest non-black neighbour outward one ring per
        # pass; masking keeps already-solid pixels exactly as they were.
        spread = rgb.filter(ImageFilter.MaxFilter(3))
        rgb = Image.composite(rgb, spread, solid)
        solid = solid.filter(ImageFilter.MaxFilter(3))

    result = rgb.convert("RGBA")
    result.putalpha(alpha)
    return result


def _pad_to_square(
    box: tuple[int, int, int, int], padding: float
) -> tuple[int, int, int, int]:
    """Grow a box by ``padding`` of its longest side, then square it up.

    The box may extend past the image bounds; the caller pastes onto a
    transparent square, so out-of-bounds simply becomes empty space and the
    subject stays centred.
    """

    left, top, right, bottom = box
    width = right - left
    height = bottom - top
    longest = max(width, height)
    edge = longest + 2 * int(round(longest * padding))
    centre_x = left + width / 2
    centre_y = top + height / 2
    half = edge / 2
    return (
        int(round(centre_x - half)),
        int(round(centre_y - half)),
        int(round(centre_x + half)),
        int(round(centre_y + half)),
    )


def assess(
    image: Image.Image,
    mask: Image.Image | None,
    box: tuple[int, int, int, int],
    framed_by_us: bool = False,
) -> tuple[Suitability, tuple[str, ...], float, bool]:
    """Rate how well the source matches the single-clear-object promise.

    This drives the optional ``Good``/``Okay``/``Poor`` badge in the ready state.
    It never blocks generation.

    ``framed_by_us`` says the frame is not the photographer's. One view cut out
    of a turnaround sheet is cropped tight to its own subject, so it touches all
    four edges and fills the frame by construction — and neither says anything
    about whether the subject was cropped when the picture was taken. Reporting
    them anyway rates every sheet "poor" on the strength of our own crop.
    """

    notes: list[str] = []
    left, top, right, bottom = box
    subject_area = max((right - left) * (bottom - top), 1)
    coverage = subject_area / float(image.width * image.height)

    touches_edge = (
        left <= 0 or top <= 0 or right >= image.width or bottom >= image.height
    )
    if mask is not None and touches_edge and not framed_by_us:
        notes.append("The object touches the frame edge and may be cropped.")

    if mask is None:
        notes.append(
            "No transparent background or mask was found, so the whole frame is used."
        )

    if coverage < 0.05:
        notes.append("The object is small in the frame, so detail may be limited.")
    elif coverage > 0.98 and mask is not None and not framed_by_us:
        notes.append("The object fills the frame, so its silhouette may be clipped.")

    if min(image.width, image.height) < 256:
        notes.append("The source image is small, so the result will be coarse.")

    cropped_short = touches_edge and coverage > 0.9 and not framed_by_us
    if mask is None or cropped_short or min(image.size) < 256:
        verdict = Suitability.POOR
    elif notes:
        verdict = Suitability.OKAY
    else:
        verdict = Suitability.GOOD

    return verdict, tuple(notes), coverage, touches_edge


def prepare(
    source_path: str | Path,
    destination: str | Path,
    mask_path: str | Path | None = None,
    padding: float = 0.08,
    size: int = 512,
) -> PreparedImage:
    """Run the full preparation sequence and write the engine input as PNG.

    Convenience wrapper over :func:`load_source` and :func:`isolate_subject` for
    callers that do not need to report progress between the two.
    """

    image = load_source(source_path)
    return isolate_subject(image, destination, mask_path, padding, size)


def isolate_subject(
    image: Image.Image,
    destination: str | Path,
    mask_path: str | Path | None = None,
    padding: float = 0.08,
    size: int = 512,
    framed_by_us: bool = False,
) -> PreparedImage:
    """Isolate the subject in an already-loaded image and write the engine input.

    PNG because the prepared image keeps an alpha channel, which the
    reconstruction engine uses to separate subject from background.

    ``framed_by_us`` is passed through to :func:`assess`; see there.
    """

    mask = resolve_mask(image, mask_path)
    box = subject_box(image, mask)
    verdict, notes, coverage, touches_edge = assess(
        image, mask, box, framed_by_us=framed_by_us
    )

    if mask is not None:
        image.putalpha(mask)

    # Before any resampling: the engine flattens this onto a solid background,
    # and undefined colour under transparent pixels would fringe the silhouette.
    if mask is not None:
        image = bleed_colour_outward(image)

    square = _pad_to_square(box, padding)
    edge = max(square[2] - square[0], 1)
    canvas = Image.new("RGBA", (edge, edge), (0, 0, 0, 0))
    # Negative offsets are handled by cropping the source to the square first;
    # Image.crop pads out-of-bounds regions with transparent pixels for RGBA.
    canvas.paste(image.crop(square), (0, 0))

    prepared = canvas.resize((size, size), Image.Resampling.LANCZOS)

    output = Path(destination)
    output.parent.mkdir(parents=True, exist_ok=True)
    prepared.save(output, format="PNG")

    return PreparedImage(
        path=output,
        size=size,
        suitability=verdict,
        notes=notes,
        had_mask=mask is not None,
        subject_coverage=coverage,
        touches_edge=touches_edge,
    )
