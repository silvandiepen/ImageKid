<template>
  <div :class="bemm()">
    <header :class="bemm('intro')">
      <p :class="bemm('eyebrow')">Features</p>
      <h1 :class="bemm('title')">What ImageKid does today.</h1>
      <p :class="bemm('intro-copy')">Current behavior is separated from planned work so the product status stays clear.</p>
    </header>
    <section :class="bemm('ledger')">
      <div :class="bemm('ledger-column')">
        <h2 :class="bemm('heading')">Available in source</h2>
        <ul :class="bemm('list')">
          <li :class="bemm('list-item')">Open images by file panel, drag and drop, URL paste, or image paste.</li>
          <li :class="bemm('list-item')">Fit, pan, pinch zoom, and reset the native viewer.</li>
          <li :class="bemm('list-item')">Sample image pixels and manage colour values in HEX, RGB, RGBA, HSL, SwiftUI, and other copy formats.</li>
          <li :class="bemm('list-item')">Export saved palettes to a local file.</li>
          <li :class="bemm('list-item')">Use free crop, ratio presets, handles, guides, and pixel dimensions.</li>
          <li :class="bemm('list-item')">Resize by exact dimensions, percentages, and presets.</li>
          <li :class="bemm('list-item')">Add editable rectangle, ellipse, line, arrow, freehand, and text annotations.</li>
          <li :class="bemm('list-item')">Export PNG, JPEG, HEIC, TIFF, BMP, and GIF from full-resolution source images and edit state.</li>
          <li :class="bemm('list-item')">Play supported local video through AVFoundation.</li>
        </ul>
      </div>
      <div :class="bemm('ledger-column')">
        <h2 :class="bemm('heading')">Not complete</h2>
        <ul :class="bemm('list')">
          <li :class="bemm('list-item')">Pixel-grid colour loupe and dominant palette extraction.</li>
          <li :class="bemm('list-item')">Blur, pixelation, annotation ordering, duplication, and rotation.</li>
          <li :class="bemm('list-item')">Undo, redo, dirty-close protection, recovery, and complete document lifecycle.</li>
          <li :class="bemm('list-item')">Metadata preservation and advanced colour-profile controls.</li>
          <li :class="bemm('list-item')">Video colour picking, crop, resize, annotations, and export. Video is playback-only today.</li>
          <li :class="bemm('list-item')">Production signing, sandbox entitlements, notarisation, and packaged distribution.</li>
        </ul>
      </div>
    </section>
    <section :class="bemm('callout')">
      <h2 :class="bemm('heading')">Deliberately deferred</h2>
      <p :class="bemm('callout-copy')">AI upscaling and model runtime work are outside the current architecture and roadmap. ImageKid is not a nonlinear video editor, photo catalogue, collaboration service, or cloud product.</p>
    </section>
  </div>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";

const bemm = useBemm("features-page", { includeBaseClass: true });
</script>
