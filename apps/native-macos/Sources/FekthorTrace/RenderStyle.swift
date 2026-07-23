import FekthorKit

// The render-style cascade helpers formerly defined here — `renderStyle` on
// `ShapeNode`/`GroupNode`, `Style.isDisplayNone`, `GraphicNode.isHiddenNode`
// — now live in FekthorKit (`RenderResolve.swift`), so the engine's own
// `GraphicRenderer` (PNG/PDF export) resolves presentation attributes and
// `display: none` identically to the canvas and thumbnails. Call sites in
// this app pick up the engine API unchanged.
