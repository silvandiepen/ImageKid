<template>
  <DocsShell>
    <div :class="bemm()">
      <p :class="bemm('eyebrow')">Workflows</p>
      <h1 :class="bemm('title')">Edit images and play local video.</h1>
      <h2 :class="bemm('heading')">View</h2>
      <p :class="bemm('copy')">Open or paste media. Images fit the available window. Pan with the mouse or trackpad, pinch to zoom, and press <kbd :class="bemm('key')">0</kbd> to fit the image again. Supported videos can be played locally.</p>
      <h2 :class="bemm('heading')">Choose an image tool</h2>
      <ul :class="bemm('list')">
        <li :class="bemm('list-item')"><kbd :class="bemm('key')">V</kbd> View</li>
        <li :class="bemm('list-item')"><kbd :class="bemm('key')">P</kbd> Pick Colour</li>
        <li :class="bemm('list-item')"><kbd :class="bemm('key')">C</kbd> Crop</li>
        <li :class="bemm('list-item')"><kbd :class="bemm('key')">D</kbd> Draw</li>
        <li :class="bemm('list-item')"><kbd :class="bemm('key')">T</kbd> Text</li>
        <li :class="bemm('list-item')"><kbd :class="bemm('key')">R</kbd> Resize</li>
        <li :class="bemm('list-item')"><kbd :class="bemm('key')">Escape</kbd> Cancel the current tool</li>
      </ul>
      <p :class="bemm('copy')">The same primary image actions are available in the native Tools and View menus. Use keyboard navigation when floating controls are hidden.</p>
      <h2 :class="bemm('heading')">Inspect image colour</h2>
      <p :class="bemm('copy')">Press and drag across an image to inspect canonical image pixels. Add useful samples to the session colour panel, choose a copy representation, or export the palette to a file.</p>
      <h2 :class="bemm('heading')">Crop and annotate images</h2>
      <p :class="bemm('copy')">Crop with edge and corner handles, guides, ratio choices, or exact pixel dimensions. Add editable shapes, lines, arrows, freehand strokes, and text. Current edits stay in session state until export.</p>
      <h2 :class="bemm('heading')">Export an image</h2>
      <p :class="bemm('copy')">Use Shift-Command-S for an image. Choose PNG, JPEG, HEIC, TIFF, BMP, or GIF and the applicable quality, scale, and transparency options.</p>
      <h2 :class="bemm('heading')">Current limitations</h2>
      <p :class="bemm('copy')">Undo and close protection are incomplete. Image export creates a fresh file without source metadata. Video has local playback only; video editing and export are not implemented.</p>
    </div>
  </DocsShell>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";
import DocsShell from "../components/DocsShell";

const bemm = useBemm("workflows-page", { includeBaseClass: true });
</script>
