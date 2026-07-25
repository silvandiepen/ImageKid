<template>
  <DocsShell>
    <div :class="bemm()">
      <header :class="bemm('header')">
        <img :class="bemm('icon')" src="/media/brand/inka.svg" alt="" width="72" height="72" />
        <div>
          <p :class="bemm('eyebrow')">Inka documentation</p>
          <h1 :class="bemm('title')">Everything Inka does.</h1>
        </div>
      </header>

      <p :class="bemm('lede')">A drawing and illustration app built around a serious brush engine, on Mac and iPad. Inka is local-first: it ships without a network entitlement, so nothing it does can reach the internet, and your work stays on your device as <code>.inka</code> files.</p>

      <h2 :class="bemm('heading')">How to: start a drawing</h2>
      <ol :class="bemm('steps')">
        <li>From the home screen pick a canvas size, or open an existing <code>.inka</code> file.</li>
        <li>Choose a brush — Ink Pen, Pencil, Charcoal, Airbrush or Marker — and set its size and colour.</li>
        <li>Draw. On a tablet or iPad, pressure and tilt drive the brush; a mouse or finger draws at full pressure.</li>
        <li><kbd>⌘S</kbd> to save your <code>.inka</code> file, or export a PNG when you are done.</li>
      </ol>

      <h2 :class="bemm('heading')">How to: shape a brush</h2>
      <ol :class="bemm('steps')">
        <li>Open the Brush panel. The preview redraws as you edit.</li>
        <li>Set the tip (hardness, roundness, angle, spacing, scatter) and the dynamics — how pressure, tilt and velocity map to size, opacity, flow, rotation and hue.</li>
        <li>Add paper grain and taper for real-media feel.</li>
        <li>Save it as an <code>.inkbrush</code> to reuse, or load one someone shared.</li>
      </ol>

      <h2 :class="bemm('heading')">How to: work with layers</h2>
      <ol :class="bemm('steps')">
        <li>Open the Layers panel to add, delete, reorder, hide, and set per-layer opacity.</li>
        <li>Strokes land on the active layer and stay editable — the canvas re-renders from the document, so nothing is baked in.</li>
        <li>Import a photo as a layer (the image button) to trace or reference over it.</li>
        <li>Undo and redo step through the whole history, non-destructively.</li>
      </ol>

      <h2 :class="bemm('heading')">How to: erase, select and transform</h2>
      <ol :class="bemm('steps')">
        <li>The eraser uses the current brush's tip and removes paint through the same engine — recorded as an erase, so it undoes cleanly.</li>
        <li>With the move tool, drag a marquee to select strokes on the active layer.</li>
        <li>Drag inside the box to move, a corner to scale, the top handle to rotate. It re-flows the vector strokes, so it stays crisp.</li>
        <li>On macOS the arrow keys nudge (⇧ for ×10) and delete removes the selection.</li>
      </ol>

      <h2 :class="bemm('heading')">How to: move around the canvas</h2>
      <ol :class="bemm('steps')">
        <li>Pan, zoom and rotate freely — scroll and pinch on the Mac, two fingers on iPad — and draw at any angle.</li>
        <li>Flip the canvas horizontally or vertically from the flip menu to check your composition.</li>
        <li><kbd>⌘0</kbd> (or Fit) resets pan, zoom, rotation and flip at once.</li>
      </ol>

      <h2 :class="bemm('heading')">How to: pick colour</h2>
      <ol :class="bemm('steps')">
        <li>Set the working colour in the Colours panel, and add swatches to the document palette.</li>
        <li>Recent colours fill in as you paint.</li>
        <li>Use the eyedropper to sample a colour straight off the canvas.</li>
      </ol>

      <h2 :class="bemm('heading')">How to: export</h2>
      <ol :class="bemm('steps')">
        <li>Export a flattened PNG, or one PNG per visible layer for hand-off.</li>
        <li>Everything flattens through the exact renderer the canvas uses, so the export matches what you drew — grain and all.</li>
        <li>Your editable source is never destroyed.</li>
      </ol>

      <h2 :class="bemm('heading')">iPad gestures</h2>
      <p :class="bemm('copy')">The Apple Pencil (or a finger) draws. Two fingers pan and pinch to zoom; twist to rotate. A two-finger tap undoes and a three-finger tap redoes. A second touch during a stroke turns it into a navigation gesture, so nothing stray is left behind.</p>
    </div>
  </DocsShell>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";
import DocsShell from "../components/DocsShell";

const bemm = useBemm("inka-docs-page", { includeBaseClass: true });
</script>
