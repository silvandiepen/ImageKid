# Fekthor focused apps

## Purpose

Fekthor's broad editor already contains useful SVG parsing, tracing, editing,
animation, export, and validation work. The focused Fekthor apps expose smaller
workflows without pretending to be a reduced Illustrator replacement.

The agreed products are:

- Fekthor Effects
- Fekthor Trace
- Fekthor Cleanup
- Fekthor View
- Fekthor Edit

All are planned products. Existing code may cover parts of their engines, but a
separate focused app is not implemented merely because the capability exists in
the flagship target.

## Shared SVG safety and preservation

Every focused Fekthor app must:

- disable scripts and event-handler execution while loading and previewing;
- block remote network resources by default;
- identify unresolved linked images, fonts, styles, and references;
- preserve unknown elements and attributes when they can be round-tripped
  safely;
- warn before an operation removes unsupported or unsafe content;
- keep a copy of the original source available until the user saves;
- write deterministically where the same input and settings should produce the
  same output;
- never overwrite the source implicitly;
- validate exported XML and references before replacing a destination file.

## Fekthor Effects

### Product definition

Fekthor Effects adds interactive states and CSS-based animation to SVG elements
without requiring the user to hand-write selectors or keyframes.

The workflow is:

1. Open or drop an SVG.
2. Select an element visually or from the element list.
3. Add a state or effect.
4. Change its properties, duration, delay, easing, and repetition.
5. Simulate the trigger in the preview.
6. Export an SVG with embedded styles or SVG plus separate CSS.

There is no general timeline in the first focused release. The interface is an
element selector, state/effect inspector, live preview, and export sheet.

### Initial triggers

- On load
- Hover
- Focus visible
- Active/pressed
- Class or attribute gate for application-controlled states

Focus behaviour must be honest. An SVG element only receives keyboard focus
when the embedding method and markup make it focusable. Effects should explain
this and offer an explicit accessibility option to add suitable focusability
markup or export a code snippet. It must not silently add `tabindex` to every
visual group.

### Initial properties

- Translate, rotate, and scale
- Transform origin
- Opacity
- Fill and stroke colour
- Stroke width
- Stroke dash array and offset
- Visibility
- Duration, delay, easing, direction, fill mode, and repeat count

These align with the current `FekthorKit` animation model. Path morphing,
arbitrary filters, JavaScript timelines, video export, and Lottie export are not
part of the first release.

### Presets

- Fade
- Lift
- Press
- Pulse
- Spin
- Wiggle
- Float
- Draw in / stroke reveal
- Colour shift
- Glow where it can be expressed with a safe supported SVG filter

Presets expand into editable state and animation values. They are not locked
black boxes.

### Preview and reduced motion

Preview chips simulate Hover, Focus, Active, and Gate states without modifying
the document. Playback respects reduced-motion settings. Exported continuous or
automatic motion is wrapped in an appropriate
`prefers-reduced-motion: no-preference` rule by default. Interactive colour and
focus changes that remain meaningful without movement may stay active.

### Export modes

- Self-contained SVG with embedded style.
- SVG plus separate CSS for inline use.
- Static SVG with all Fekthor-owned animation classes and styles removed.
- Copy HTML/CSS example showing the required embedding and focus behaviour.

The export screen must explain that CSS targeting inside an SVG does not behave
identically when used inline, through `<object>`, as a background, or through an
`<img>` element. The preview should let the user test the supported embedding
modes.

### Release gate

An exported effect must match the app preview in current Safari, Chrome, and
Firefox fixtures for every advertised trigger/property combination. Export must
remain usable without Fekthor metadata.

### Proposed identity

- Target: `FekthorEffects`
- Display name: `Fekthor Effects`
- Proposed bundle id: `com.hakobs.fekthor.effects`

## Fekthor Trace

### Product definition

Fekthor Trace turns raster artwork into editable SVG paths. The focused app is
successful only when the result is useful as vector artwork, not merely when it
resembles the source at preview size.

The workflow is:

1. Drop or paste one or more raster images.
2. Choose Automatic, Shapes, Strokes, or Gradient mode.
3. Preview source and trace with Split, Overlay, and Wipe comparison.
4. Adjust a short set of mode-relevant controls or use Auto-tune.
5. Inspect path count, colours, nodes, dimensions, and estimated SVG size.
6. Export SVG or copy it to the clipboard.

### Product boundary

Trace may include crop, background/alpha treatment, palette limits, smoothing,
corner preservation, speck removal, path simplification, and output sizing when
they directly improve tracing. General path editing belongs to Fekthor Edit or
the flagship Fekthor editor.

### Quality gate

Before release, build a representative fixture set covering:

- flat icons and logos;
- line drawings;
- screenshots and UI artwork;
- clay or rendered isolated objects;
- transparent edges;
- gradients;
- noisy photos that should be rejected or clearly marked unsuitable.

Score visual similarity, path count, node count, closed-path correctness,
editability, colour accuracy, thin-stroke continuity, transparent-edge quality,
file size, and processing time. The app must identify inputs it cannot trace
well instead of implying that every image can become clean vector artwork.

### Explicit exclusions

- Cloud vectorization fallback.
- Generative reconstruction of unseen detail.
- Full vector drawing workspace.
- Automatic font identification or logo recreation promises.

### Existing implementation note

Tracing already exists inside `FekthorKit`, and the broad editor currently uses
the source target name `FekthorTrace`. That target is not the focused product
defined here. Resolve the target naming before adding a separate release target
so build schemes, bundle identities, and documentation remain unambiguous.

### Proposed identity

- Target: `FekthorTraceApp` until the flagship target is renamed
- Display name: `Fekthor Trace`
- Proposed bundle id: `com.hakobs.fekthor.trace`

## Fekthor Cleanup

### Product definition

Fekthor Cleanup repairs, normalises, and reduces SVG files while showing exactly
what will change. Its default operation should preserve the rendered result.

The workflow is:

1. Drop one SVG, several SVGs, or a folder.
2. Scan for problems and unnecessary source.
3. Review safe fixes, appearance-changing fixes, and unsafe content separately.
4. Preview the original and cleaned result.
5. Export cleaned copies and a concise report.

### Safe fixes

- Remove editor metadata, comments, and unused definitions.
- Remove empty groups and redundant attributes.
- Collapse safe group/transform structures.
- Normalise numeric precision.
- Normalise colour syntax and presentation attributes.
- Repair missing or inconsistent dimensions when the viewBox is sufficient.
- Tighten the viewBox to visible bounds with explicit optional padding.
- Deduplicate identical gradients, clip paths, masks, and symbols.
- Repair broken internal IDs and references where the intended target is clear.
- Sort or stabilise serialisation for deterministic output.

### Optional appearance-changing fixes

- Convert strokes to outlines.
- Flatten transforms.
- Simplify paths.
- Reduce colour count.
- Remove hidden or off-canvas artwork.
- Replace unsupported filters or effects.

These are off by default and must show a visual warning. Cleanup must not use a
smaller file size as permission to change appearance silently.

### Reporting

For each file show:

- original and output byte size;
- elements, paths, nodes, definitions, and IDs before and after;
- warnings and unresolved references;
- operations applied;
- whether pixel-difference comparison passed at tested render sizes.

### Release gate

Safe-clean fixtures must render within a defined pixel-difference tolerance in
multiple renderers, preserve accessibility labels and titles, and round-trip
foreign but valid content that was not selected for removal.

### Proposed identity

- Target: `FekthorCleanup`
- Display name: `Fekthor Cleanup`
- Proposed bundle id: `com.hakobs.fekthor.cleanup`

## Fekthor View

### Product definition

Fekthor View is a fast native SVG viewer. By default it simply shows the SVG,
including supported animation. Inspection is available when needed, but the
app does not open with a permanent developer panel.

The default window contains the artwork and minimal controls for open, fit,
zoom, background, and animation playback. The inspector appears through a
toolbar action, menu item, or keyboard shortcut and remembers whether the user
left it open.

### Viewing

- Fit, actual size, zoom, pan, and centre.
- Transparent checkerboard plus light, dark, and custom backgrounds.
- Show intrinsic size, viewBox, and rendered size unobtrusively.
- Play CSS and supported SMIL animation when safe.
- Pause, restart, scrub when a duration can be determined, and respect reduced
  motion.
- Simulate hover, focus, and active states for interactive SVGs.
- Compare light and dark page contexts.
- Open multiple files in separate windows and support Quick Look-style keyboard
  navigation for a selected folder.

### Optional inspector

- Searchable element tree.
- Click artwork to reveal its source element.
- Element tag, ID, classes, bounds, transform, opacity, fill, stroke, and
  accessibility name.
- Referenced gradient, pattern, mask, clip path, symbol, and filter.
- Document fonts, colours, IDs, definitions, linked resources, scripts, event
  handlers, and validation warnings.
- Copy an element, path data, selector, colour, or complete SVG source.
- Raw source view with selection linked to the visual tree.

The inspector is read-only. Any mutation routes to Fekthor Edit or is exposed as
an explicit **Open in Fekthor Edit** action when that app is available.

### Security

View must never become a convenient way to execute untrusted SVG. Scripts and
event handlers stay inert, external resource access is blocked, and the
inspector reports what was disabled. Do not use an unrestricted web view simply
because it reproduces animation more easily.

### Explicit exclusions

- Saving edits.
- General raster-image viewing.
- Browser developer tools.
- Network fetching of linked assets.
- Converting or tracing files.

### Proposed identity

- Target: `FekthorView`
- Display name: `Fekthor View`
- Proposed bundle id: `com.hakobs.fekthor.view`

## Fekthor Edit

### Product definition

Fekthor Edit is a basic native SVG correction tool. It opens a single SVG and
lets the user make common visual and structural changes without creating a
workspace or learning the full Fekthor editor.

It is not Fekthor Lite. The scope is defined by correction tasks, not by taking
an arbitrary subset of the flagship toolbar.

### Initial editing scope

- Select one or more elements visually or from the element tree.
- Move, scale, rotate, duplicate, reorder, group, ungroup, and delete.
- Edit path nodes and Bezier handles.
- Change fill, stroke, stroke width, opacity, line cap, and line join.
- Edit basic linear and radial gradients.
- Change document width, height, and viewBox.
- Crop the canvas to artwork bounds or a drawn rectangle, with exact padding.
- Add basic rectangle, ellipse, line, and path shapes.
- Edit text content and basic typography when fonts remain available.
- Undo and redo.
- Save a copy, replace with confirmation, or export cleaned SVG.

### Inspector

The inspector uses the same document/element information as Fekthor View, but
exposes supported values as controls. Unsupported attributes remain visible and
round-tripped. Raw source editing is read-only in the first release to avoid a
second code editor, parser state conflicts, and invalid partial documents.

### Explicit exclusions

- Folder workspaces and asset galleries.
- Design-token libraries and workspace-wide style propagation.
- Advanced Boolean, mesh, brush, perspective, or typography systems.
- Raster tracing.
- Animation authoring.
- Plugin APIs.
- Cloud or generative tools.

An SVG that needs these capabilities can be opened in the flagship Fekthor app.
Edit still completes every advertised basic correction on its own.

### Round-trip requirement

Saving one supported change must not rewrite or discard unrelated SVG content.
Unknown valid elements, namespaces, metadata, accessibility content, and styles
must survive unless the user explicitly chooses cleanup that removes them.

### Proposed identity

- Target: `FekthorEdit`
- Display name: `Fekthor Edit`
- Proposed bundle id: `com.hakobs.fekthor.edit`

## Shared release work

Before the focused suite branches into separate app targets:

1. Isolate secure SVG loading and resource resolution in `FekthorKit`.
2. Make parse, validate, render, mutate, and serialize APIs usable without the
   flagship workspace controller.
3. Add round-trip fixtures for unknown valid SVG content.
4. Add renderer comparison fixtures for static and animated SVG.
5. Define a shared document session that each app can configure as read-only,
   basic-edit, effects-edit, cleanup, or trace mode.
6. Keep app-specific UI and product decisions inside each app target.
7. Add signing, sandbox entitlements, document types, icons, and App Store
   metadata separately for each product.

Sharing engines must not turn the focused apps into modes inside one executable.
Their value is that each opens directly into the job named by the product.
