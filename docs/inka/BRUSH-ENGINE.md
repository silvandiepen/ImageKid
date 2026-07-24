# Inka brush engine reference

The brush engine is Inka's reason to exist and the family's shared painting
core. It lives in two packages — `BrushKit` (portable, CPU-testable) and
`BrushRender` (the Metal live path) — and knows nothing about Inka's document or
UI, so ImageKid can adopt it later (see [PLAN.md](PLAN.md), P7).

Status: the model, dab generation, both renderers, grain, dynamics, `.inkbrush`
codec and the built-in presets described here are **implemented and tested**
(BrushKit 39 tests, BrushRender 4). Fields the generator does not yet read are
called out inline.

## Mental model

Painting is three stages, each a pure step you can test in isolation:

```
StrokeInput  ──smooth──►  BrushEngine.dabs()  ──►  [Dab]  ──stamp──►  pixels
(captured input)          (deterministic)          (stamps)    CPU reference / Metal
```

1. **`StrokeInput`** — the captured path (positions + pressure/tilt/velocity/
   time), platform-neutral.
2. **`BrushEngine`** — turns the path into evenly-spaced **stamps** (`Dab`s),
   applying the brush's dynamics. Pure and deterministic.
3. **A renderer** — draws the dabs. `ReferenceRenderer` (CoreGraphics, the
   tests/CLI/export path) and `BrushCompositor` (Metal, the live canvas) stamp
   the *same* dabs, so they agree.

All geometry is in **canvas pixel space, top-left origin** — the app converts
its view/normalised coordinates before handing input over.

## `StrokeInput` and smoothing

`StrokeSample` carries `position`, `pressure` (0…1), `altitude` (pen tilt: π/2
upright, 0 flat), `azimuth` (tilt bearing), `velocity` (pt/s), `timestamp`.
`StrokeInput` wraps `[StrokeSample]` and offers:

- `withDerivedVelocity()` — fills `velocity` from consecutive timestamps where
  the app only sent positions.
- `smoothed(amount:passes:)` — a simple neighbour-average low-pass (endpoints
  pinned). Kept for tests and callers that want cheap smoothing.
- `oneEuroSmoothed(minCutoff:beta:)` — the **1€ filter** (`OneEuroFilter`), the
  adaptive low-latency smoother the engine uses live: it smooths hard when the
  pen moves slowly (kills tremor) and barely at all when it moves fast (kills
  lag). Endpoints pinned; samples without a time delta pass through.
- `sample(atArcLength:)` — interpolates a sample at a distance along the spine,
  the primitive the even-spacing walk is built on.

The engine applies `oneEuroSmoothed` when `brush.smoothing > 0`, mapping
`smoothing` 0…1 to `minCutoff = 4.5 − 4.1·smoothing` (β 0.02). `smoothing == 0`
leaves the raw spine (the deterministic-test path).

## The `Brush` preset

A `Brush` is the serialized `.inkbrush` document. Every field has a sensible
default, so a minimal brush is `Brush(name:)`. Sizes are in canvas points.

| Field | Meaning |
| --- | --- |
| `id`, `name` | stable identity a `BrushStroke` references; display name |
| `size` | base stamp diameter (pt), before dynamics |
| `flow` | per-dab alpha (paint laid per stamp) |
| `opacity` | ceiling alpha for the whole stroke |
| `smoothing` | live 1€ smoothing 0…1 |
| `blendMode` | stroke compositing name (app maps it) |
| `tip` | footprint — see below |
| `dynamics` | how input drives the stamp — see below |
| `grain` | paper tooth — see below |
| `taper` | end ramps — see below |

### `Tip`

| Field | Meaning |
| --- | --- |
| `shape` | `round` · `square` (Chebyshev falloff) · `textured` (falls back to round until stamp textures land) |
| `stampTexture` | named stamp for `textured` (reserved) |
| `hardness` | soft edge: 1 crisp … 0 fully feathered |
| `roundness` | 1 circle → 0 a thin ellipse (calligraphic nib) |
| `angle` | nib angle (radians) |
| `spacing` | gap between stamps as a fraction of the current diameter (0.05 dense) |
| `scatter` | random per-dab offset, fraction of diameter |

### `Dynamics`

Each `…To…` field is a 0…1 amount the (shaped) input modulates. The generator
reads all of these today.

| Field | Effect |
| --- | --- |
| `pressureToSize` / `pressureToOpacity` / `pressureToFlow` | pressure thins/fades the dab |
| `velocityToSize` / `velocityToOpacity` | fast strokes thin/fade (speed ≈ 4000 pt/s = "fast") |
| `tiltToSize` | a pen laid flat widens (shading) |
| `tiltToAngle` | 1 = the nib fully follows the pen's azimuth |
| `sizeJitter` / `angleJitter` / `hueJitter` | per-dab random variation |
| `pressureCurve` / `velocityCurve` | `ResponseCurve` shaping the raw input first |

**Response curves** (`ResponseCurve`: `linear`, `easeIn`, `easeOut`,
`easeInOut`) shape the raw pressure/speed before the amounts use them — the
difference between a linear pen and one that feels alive (e.g. a pencil that
barely marks under light pressure is an `easeIn`).

### `Grain`

Paper tooth, so a pencil reads as pencil. Procedural — no bitmap assets.

| Field | Meaning |
| --- | --- |
| `depth` | pit depth 0…1 (0 = smooth) |
| `scale` | tooth coarseness (relative; ×8 pt cell) |
| `texture` | named grain (reserved; procedural today) |
| `movingWithStroke` | reserved; grain is canvas-fixed today |

### `Taper`

`startLength` / `endLength` (pt) and `startSize` / `endSize` (0…1 diameter
fraction) ramp the stroke ends to a point.

## Dab generation

`BrushEngine.dabs(for:brush:color:seed:) -> [Dab]` is the deterministic heart:

1. `withDerivedVelocity()` then 1€ smooth (if `smoothing > 0`).
2. A single-sample tap emits **one** dab.
3. Otherwise walk the arc length, placing a dab each step, where
   `step = max(0.5, tip.spacing · currentDiameter)` — so a pressure-swelling
   stroke keeps a constant *visual* dab density.
4. Per dab, from the interpolated sample:
   - `pressure = pressureCurve(sample.pressure)`, `fast = velocityCurve(v/4000)`,
     `flatness = 1 − altitude/(π/2)`.
   - **size** = `base · (1 − pressureToSize·(1−pressure)) · (velocity, tilt) ·
     taper · (1 − sizeJitter·rand)`.
   - **alpha** = `flow · (pressure/velocity opacity terms)`, capped at `opacity`.
   - **angle** = `tip.angle` blended toward `azimuth` by `tiltToAngle`, plus
     `angleJitter`.
   - **scatter** offsets the position on a random disc.
   - **hue** rotated by `±hueJitter·½turn` (`RGBA.hueShifted`).
   - grain (`grainDepth/grainCell/grainSeed`) and `square` are copied onto the
     `Dab` for the renderer.

### Determinism

Jitter comes from a seeded **`SplitMix64`** (pure integer math), never
`Math.random`. The same stroke + brush + `seed` always yields the same dabs —
tests and Inka's non-destructive re-rasterization both depend on this. A
`BrushStroke` stores its `seed`, so re-rendering is identical.

## `Dab`

The render unit — everything already resolved from input + brush, so renderers
do no dynamics: `position`, `diameter`, `angle`, `roundness`, `alpha`,
`hardness`, `color` (`RGBA`), `grainDepth`/`grainCell`/`grainSeed`, `square`.

## Grain noise (`GrainNoise`) — CPU/GPU parity

Grain is bilinearly-interpolated value noise sampled in **canvas space**, so it
stays pinned to the "paper" as strokes cross it. The integer hash + smoothstep
are written once in Swift (`GrainNoise`) and mirrored **byte-for-byte in the
Metal shader** (`DabShaders`), so the CPU reference renderer and the GPU live
canvas show the same tooth (a `BrushRender` test asserts the fraction of ink
removed matches within tolerance).

> Grain is a *rendering* effect on coverage, not part of dab generation. Under a
> fully opaque (`flow` 1, `opacity` 1) brush the overlapping dabs fill the tooth
> in — correct: a solid marker covers the paper. Grain reads on low-flow media
> (Pencil, Charcoal).

## Renderers

Both consume `[Dab]` and are top-left origin.

- **`ReferenceRenderer`** (CoreGraphics, CPU) — the tests/CLI/export/flatten
  path. Round dabs draw as a radial-gradient disc (hardness = the solid-core
  fraction); grained or square dabs take a per-pixel path (radial or Chebyshev
  falloff × canvas-space grain). Not the live path, but the ground truth.
- **`BrushCompositor`** (Metal, `BrushRender`) — the live canvas. One instanced
  quad per dab; the fragment computes the falloff (round `length`, square
  `max(|x|,|y|)`) with a `smoothstep` hardness edge and canvas-space grain;
  premultiplied "over" blending. The shader is compiled at runtime from a source
  string (`DabShaders`) because SwiftPM's command-line build doesn't compile
  `.metal`, which would make the package untestable from the terminal.

## `.inkbrush` format

`InkBrushCoding.encode/decode` — one versioned JSON object,
`{ "version": 1, "brush": { … } }`, pretty-printed with sorted keys. The
`Dynamics` decoder tolerates older files missing the response-curve fields
(they default to `linear`), so the format can grow without breaking saved
brushes.

## Built-in presets (`BrushLibrary`)

Fixed ids so saved strokes keep resolving: **Ink Pen** (crisp), **Pencil**
(easeIn pressure + graphite grain + taper), **Charcoal** (heavy grain, tilt
widen, scatter), **Airbrush** (soft, low flow), **Marker** (flat, calligraphic,
translucent). `BrushLibrary.all` seeds every document's brush table.

## Adding a brush

- **A preset:** add a `Brush(...)` to `BrushLibrary` with a new stable `id`, or
  ship an `.inkbrush` file the user imports (Inka's brush editor loads them).
- **A new tip shape / grain mode:** add the field to `Brush`, thread it onto
  `Dab` in `BrushEngine`, and implement it in **both** renderers
  (`ReferenceRenderer` per-pixel path and the `DabShaders` fragment) — keep them
  in lockstep, and add a cross-renderer agreement test in `BrushRenderTests`.

## Testing

- `swift test` in `packages/BrushKit` — spacing/resample, dynamics curves, tilt,
  hue, grain (single-dab), square tips, 1€ smoothing, `.inkbrush` round-trip,
  orientation.
- `swift test` in `packages/BrushRender` — offscreen Metal render, GPU/CPU
  coverage agreement, grain agreement, accumulation.
- `swift run brush <dir>` — render the canonical S-curve with every built-in to
  PNG for eyeballing/regression.
