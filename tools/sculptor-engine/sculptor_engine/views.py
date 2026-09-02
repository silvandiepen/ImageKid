"""Finding several views of one object inside a single image.

A generated "turnaround" sheet — front, side and back laid out in a row or a
grid — is a natural thing to hand this tool, and a very unnatural thing to
reconstruct: fed in whole it produces one lumpy object with three faces on it.

Splitting is deliberately structural rather than clever. Content is projected
onto each axis and the empty bands between subjects are the cuts. That works on
exactly the images this needs to work on — renders on a flat or transparent
background, laid out on a grid — and declines on everything else instead of
guessing, because a wrong split is worse than no split.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from PIL import Image

#: A gutter must be at least this fraction of the image's size to count as a
#: separator rather than a gap inside one subject — between a pair of legs, say.
MINIMUM_GUTTER = 0.03

#: Cells smaller than this fraction of the largest are treated as debris: a
#: caption, a stray mark, a drop shadow that missed its subject.
MINIMUM_CELL_AREA_SHARE = 0.15

#: More cells than this and it is a sprite sheet or a catalogue page, not a
#: turnaround of one object.
MAXIMUM_CELLS = 12

#: Separate regions of content to look at before giving up. Captions push this
#: far higher than the cell count — a six-panel sheet with labels came to 65
#: pieces, 59 of them letters — but a page of thousands is something else
#: entirely and not worth measuring.
MAXIMUM_PIECES = 400

#: Alpha at or below this is background.
ALPHA_THRESHOLD = 8

#: Without alpha, a pixel this far from the background colour counts as content.
COLOUR_TOLERANCE = 18

#: A pixel closer to the background than this share of the subject's own
#: contrast is a shadow, not the subject.
#:
#: Relative, not absolute, and that is the whole point: a fixed threshold high
#: enough to drop a shadow would erase a pale subject entirely. Measured on a
#: real sheet, the animal sits a median distance of 204 from the white backdrop
#: while its drop shadow occupies a thin tail below 100 — 4% of the "content".
#: On a sheet rendered without shadows nothing at all falls below 158, so this
#: removes nothing there. A subject that is itself faint pulls the cut down with
#: it and keeps everything.
SHADOW_SHARE = 0.35


@dataclass(frozen=True)
class Cell:
    """One view found inside a sheet."""

    box: tuple[int, int, int, int]
    image: Image.Image

    @property
    def area(self) -> int:
        left, top, right, bottom = self.box
        return max(right - left, 0) * max(bottom - top, 0)


def has_alpha(image: Image.Image) -> bool:
    """Whether the image carries a usable cutout of its own."""

    return bool(np.asarray(image.convert("RGBA"))[:, :, 3].min() <= ALPHA_THRESHOLD)


def content_mask(image: Image.Image) -> np.ndarray:
    """Boolean mask of pixels that are not background.

    Alpha decides it when present. Otherwise the background colour is taken
    from the corners — a render on a flat backdrop, which is what these sheets
    are — and anything far enough from it is content.
    """

    rgba = image.convert("RGBA")
    data = np.asarray(rgba)
    alpha = data[:, :, 3]

    if alpha.min() <= ALPHA_THRESHOLD:
        return alpha > ALPHA_THRESHOLD

    rgb = data[:, :, :3].astype(np.int16)
    corners = np.stack(
        [rgb[0, 0], rgb[0, -1], rgb[-1, 0], rgb[-1, -1]]
    ).astype(np.int16)
    # Median of the corners, so one corner overlapped by a subject cannot
    # define the background on its own.
    background = np.median(corners, axis=0)
    distance = np.abs(rgb - background).max(axis=2)

    content = distance > COLOUR_TOLERANCE
    if not content.any():
        return content

    # Drop the drop shadow. A shadow is the backdrop darkened, so it sits far
    # closer to the background than the subject does — and left in, it is not a
    # harmless smudge: the engine reconstructs it as a solid plate under the
    # animal's feet, and it inflates the panel's bounding box besides.
    strength = float(np.median(distance[content]))
    return distance > max(strength * SHADOW_SHARE, COLOUR_TOLERANCE)


def _bands(occupied: np.ndarray, minimum_gap: int) -> list[tuple[int, int]]:
    """Runs of occupied rows or columns, separated by gaps of at least
    ``minimum_gap``."""

    bands: list[tuple[int, int]] = []
    start: int | None = None
    gap = 0

    for index, is_occupied in enumerate(occupied):
        if is_occupied:
            if start is None:
                start = index - gap if gap and bands else index
            gap = 0
            continue
        if start is None:
            continue
        gap += 1
        if gap >= minimum_gap:
            bands.append((start, index - gap + 1))
            start = None
            gap = 0

    if start is not None:
        bands.append((start, len(occupied)))
    return bands


def _cut_out(
    image: Image.Image,
    box: tuple[int, int, int, int],
    mask: np.ndarray,
    carries_own_cutout: bool,
) -> Image.Image:
    """Crop one cell, carrying the background mask with it.

    This matters more than it looks. A sheet on a white backdrop has no alpha,
    so a plain crop hands the reconstruction engine a subject on white — and
    the engine, with nothing to say where the object ends, reconstructs the
    picture as a flat card. The split already knows what is background; the
    crop has to keep that knowledge.

    Holes are filled first, because the mask comes from colour distance and a
    white patch on the subject is the same colour as the backdrop behind it.
    Anything fully enclosed by the subject is part of the subject.
    """

    crop = image.crop(box).convert("RGBA")
    if carries_own_cutout:
        return crop

    from scipy.ndimage import binary_fill_holes

    left, top, right, bottom = box
    region = binary_fill_holes(mask[top:bottom, left:right])
    crop.putalpha(Image.fromarray(np.where(region, 255, 0).astype(np.uint8), mode="L"))
    return crop


def find_cells(image: Image.Image) -> list[Cell]:
    """Split a sheet into its views, or return ``[]`` if it is one subject.

    Works on connected regions of content rather than on gaps in a projection.
    A projection has to be told how wide a gap counts as a separator, and there
    is no such width: on a real sheet the space between two panels was 32 pixels
    while the space between an animal's legs was 40, so any threshold either
    merges two views or saws one in half.

    Connected regions have no such knob. Two panels are separate because they do
    not touch. It also disposes of the captions a sheet prints under each panel:
    on that same sheet the smallest subject covered 77,000 pixels and the
    largest letter 190, so telling a view from a label is not a close call.

    Returns cells in reading order: left to right, top to bottom.
    """

    mask = content_mask(image)
    if not mask.any():
        return []

    from scipy.ndimage import find_objects, label

    pieces, count = label(mask)
    if count < 2:
        return []
    if count > MAXIMUM_PIECES:
        # A page of many small things is a catalogue or a texture, not a
        # turnaround. Bail before doing the work of measuring them all.
        return []

    sizes = np.bincount(pieces.ravel())[1:]
    boxes = find_objects(pieces)
    biggest = int(sizes.max())

    subjects = [
        (int(size), box)
        for size, box in zip(sizes, boxes)
        if size >= biggest * MINIMUM_CELL_AREA_SHARE
    ]
    if len(subjects) < 2 or len(subjects) > MAXIMUM_CELLS:
        return []

    # Several views of one object are near enough the same size. Anything wildly
    # uneven is more likely a subject beside something else entirely.
    if min(size for size, _ in subjects) < biggest * 0.25:
        return []

    carries_own_cutout = has_alpha(image)
    cells = [
        Cell(
            box=(box[1].start, box[0].start, box[1].stop, box[0].stop),
            image=_cut_out(
                image,
                (box[1].start, box[0].start, box[1].stop, box[0].stop),
                mask,
                carries_own_cutout,
            ),
        )
        for _, box in subjects
    ]
    # Reading order: down the page in rows, then across. Panels rarely line up
    # to the pixel, so cells are bucketed into rows a panel-height deep rather
    # than sorted on their exact tops. Measured before sorting, because
    # ``list.sort`` makes the list look empty while the key runs.
    row_height = max(cell.box[3] - cell.box[1] for cell in cells)
    cells.sort(key=lambda cell: (cell.box[1] // row_height, cell.box[0]))

    if not _tiles_a_grid(cells):
        return []
    return cells


def _tiles_a_grid(cells: list[Cell]) -> bool:
    """Whether these cells are laid out as a sheet rather than found in one.

    The check that separates a turnaround from a single subject that happens to
    come apart. Connected regions will split anything: a ship photographed from
    above, pale against a pale background, breaks into a hull and some cabins,
    and without this those pieces are read as four viewpoints and a model is
    carved from four copies of the same picture.

    A sheet tiles. Its panels sit in rows, and within a row they occupy
    separate columns — so no two panels overlap when projected onto either
    axis. The parts of one subject overlap constantly, because they are stacked
    on top of each other. No threshold is involved, which is the point: the
    gutter width that told a cow's panels apart was narrower than the gap
    between its own legs.
    """

    rows: list[list[Cell]] = []
    for cell in cells:
        top, bottom = cell.box[1], cell.box[3]
        for row in rows:
            lowest = min(member.box[1] for member in row)
            highest = max(member.box[3] for member in row)
            overlap = min(bottom, highest) - max(top, lowest)
            shorter = min(bottom - top, highest - lowest)
            if shorter > 0 and overlap > shorter * 0.5:
                row.append(cell)
                break
        else:
            rows.append([cell])

    # Panels in one row occupy separate columns.
    for row in rows:
        spans = sorted((member.box[0], member.box[2]) for member in row)
        for (_, first_right), (second_left, _) in zip(spans, spans[1:]):
            if second_left < first_right:
                return False

    # And the rows themselves do not run into each other.
    bands = sorted(
        (min(m.box[1] for m in row), max(m.box[3] for m in row)) for row in rows
    )
    for (_, first_bottom), (second_top, _) in zip(bands, bands[1:]):
        if second_top < first_bottom:
            return False

    return True


@dataclass(frozen=True)
class Label:
    """A piece of text found on a sheet, and where it sits.

    Coordinates are fractions of the image, origin top left, so the app can
    report what its text recogniser saw without either side agreeing on pixels.
    """

    text: str
    x: float
    y: float


#: How far below a panel its caption may sit, as a fraction of the sheet's
#: height. Captions sit just under their picture; anything further away belongs
#: to something else, or to nothing.
CAPTION_REACH = 0.12


def match_labels(
    cells: list[Cell], labels: list[Label], size: tuple[int, int]
) -> list[str | None]:
    """Which view each cell is, according to the sheet's own captions.

    A caption sits under its picture and within its width. That is the whole
    rule — it needs no OCR of its own, only the text and where it was found,
    which the app's recogniser already provides.

    Returns one name per cell, ``None`` where no caption claimed it. Partial
    answers are useful: the caller can fall back for the cells it cannot name
    rather than discarding the ones it can.
    """

    from .multiview import VIEW_SYNONYMS

    width, height = size
    names: list[str | None] = [None] * len(cells)
    if not width or not height:
        return names

    for label in labels:
        cleaned = " ".join(label.text.lower().split()).strip(".:-–—")
        name = VIEW_SYNONYMS.get(cleaned)
        if name is None:
            continue

        x, y = label.x * width, label.y * height
        best: int | None = None
        best_gap = CAPTION_REACH * height

        for index, cell in enumerate(cells):
            left, top, right, bottom = cell.box
            if not left <= x <= right:
                continue
            gap = y - bottom
            # Below the panel, not above it and not inside it.
            if 0 <= gap < best_gap:
                best, best_gap = index, gap

        if best is not None and names[best] is None:
            names[best] = name

    return names


def looks_like_a_sheet(image: Image.Image) -> bool:
    """Whether the image holds several views rather than one subject."""

    return len(find_cells(image)) >= 2
