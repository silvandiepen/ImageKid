# Testing strategy

## Objectives

Testing must prove that ImageKid is precise, offline, non-destructive, colour-correct, frame-accurate, accessible, and stable under long local processing jobs.

## Unit tests

### Coordinates

Cover:

- source-to-view and view-to-source conversion;
- image orientation and video preferred transforms;
- Retina backing scale;
- fractional zoom;
- crop offsets;
- resize and upscale output mapping;
- points outside media bounds;
- video annotations at timestamp boundaries.

### Domain state

Cover:

- edit-state mutations;
- annotation geometry, order, style, and time ranges;
- undo/redo coalescing;
- dirty-state transitions;
- close and replacement decisions;
- export configuration validation.

### Colour

Cover:

- channel order and alpha;
- sRGB conversion;
- embedded image profiles;
- full- and video-range YCbCr conversion;
- common video colour matrices and transfer functions;
- transparent-edge premultiplication;
- stable sample results at different zoom levels.

### Tiling

Cover:

- exact tile coverage;
- overlap and padding;
- edge tiles;
- model alignment requirements;
- adaptive tile sizes;
- cancellation;
- deterministic output independent of tile order.

## Golden image tests

Use checked-in small fixtures with known rights and generated patterns.

Compare:

- crop and standard resize;
- annotation rasterisation at several output scales;
- text positioning and baseline;
- blur and pixelation regions;
- alpha recombination;
- tile seams;
- colour-profile conversion;
- Core ML output against a pinned reference implementation within defined tolerances.

Golden files must be reviewed deliberately when they change; tests must not auto-update them.

## Video fixture tests

Create short synthetic clips containing:

- moving colour patches;
- frame numbers burned into pixels;
- variable and constant frame rates;
- rotation metadata;
- audio sync markers;
- scene cuts;
- transparency where supported;
- different colour matrices and ranges;
- silent clips and multiple audio layouts.

Validate:

- duration;
- presentation timestamps;
- frame order and count where determinable;
- orientation;
- crop and output dimensions;
- annotation visibility at exact start/end times;
- audio start, end, and drift;
- cancellation and atomic output;
- codec/container compatibility errors.

## Model quality suite

Maintain a curated local benchmark set:

- photographs;
- faces;
- hair and fine texture;
- architecture and repetitive patterns;
- UI screenshots and small text;
- icons, line art, pixel art, and illustrations;
- noisy and JPEG-compressed media;
- transparent assets;
- adjacent video frames with slow and fast motion;
- scene cuts.

Evaluate:

- detail recovery;
- hallucinated detail;
- text corruption;
- facial distortion;
- colour and luminance shift;
- edge halos;
- tile seams;
- temporal shimmer;
- performance and memory.

Automated metrics may support review but cannot replace visual inspection. Model changes require side-by-side sign-off on the entire set.

## Offline tests

Release tests MUST run with networking disabled and prove:

- first launch succeeds;
- every included model loads;
- image and video upscaling complete;
- no runtime download prompt appears;
- no network permission or endpoint is required;
- model and licence information remains available locally.

A build audit should search for unexpected networking dependencies and endpoints.

## Performance tests

Record results by Mac model, memory, macOS version, model version, compute units, tile size, and codec.

Measure:

- launch time;
- image open-to-preview time;
- video open-to-first-frame time;
- zoom, pan, and playback responsiveness;
- palette extraction time;
- image megapixels per second;
- video processing frames per second;
- encoder throughput;
- peak resident memory;
- temporary disk use;
- cancellation latency;
- thermal and sustained-job behaviour.

Minimum hardware is chosen from measured results, not assumptions.

## Accessibility tests

Manually and automatically verify:

- full keyboard operation;
- VoiceOver labels, roles, values, and announcements;
- stable focus when floating controls appear;
- annotation accessibility navigation;
- crop and resize without pointer precision;
- Increased Contrast;
- Reduce Transparency;
- Reduce Motion;
- large text and display scaling;
- colour swatches with textual values.

## UI tests

Automate critical flows:

1. Open image, pick colour, copy value.
2. Crop, annotate, undo, redo, export PNG.
3. Run standard resize and AI preview.
4. Open video, scrub, step frame, pick colour.
5. Add a timed annotation and export video.
6. Cancel a long upscale without losing edits.
7. Close with unexported changes.
8. Handle unsupported or protected media.

## Reliability and fault injection

Test:

- insufficient disk space;
- denied save access;
- model load failure;
- memory pressure;
- interrupted export;
- malformed metadata;
- damaged media;
- unsupported pixel formats;
- audio passthrough incompatibility;
- app termination during a long job;
- stale preview results arriving after the session changes.

## Release gate

A release is blocked when:

- a model lacks verified redistribution terms or notices;
- offline processing fails;
- output geometry differs from preview beyond tolerance;
- colour picking is zoom-dependent;
- video duration or audio sync changes unexpectedly;
- visible tile seams occur on the benchmark set;
- cancellation corrupts output;
- a core workflow is not keyboard accessible;
- minimum-hardware memory limits are exceeded.