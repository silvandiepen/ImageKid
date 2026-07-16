<template>
  <div :class="bemm()">
    <header :class="bemm('intro')">
      <div :class="bemm('intro-copy-wrap')">
        <p :class="bemm('eyebrow')">Features</p>
        <h1 :class="bemm('title')">What ImageKid does today.</h1>
        <p :class="bemm('intro-copy')">A focused native toolkit for common image work. Current behavior is separated from planned work so the product boundary stays clear.</p>
      </div>
      <ProductPreview compact />
    </header>

    <section :class="bemm('section')">
      <div :class="bemm('section-heading')">
        <p :class="bemm('eyebrow')">Current build</p>
        <h2 :class="bemm('heading')">Available in source</h2>
      </div>
      <div :class="bemm('feature-grid')">
        <article v-for="feature in currentFeatures" :key="feature.title" :class="bemm('feature-card')">
          <span :class="bemm('feature-status')">Available in source</span>
          <h3>{{ feature.title }}</h3>
          <p>{{ feature.copy }}</p>
        </article>
      </div>
    </section>

    <section :class="bemm('section')">
      <div :class="bemm('section-heading')">
        <p :class="bemm('eyebrow')">Release boundary</p>
        <h2 :class="bemm('heading')">Not complete</h2>
      </div>
      <div :class="bemm('incomplete-grid')">
        <article v-for="item in incompleteFeatures" :key="item.title" :class="bemm('incomplete-card')">
          <h3>{{ item.title }}</h3>
          <p>{{ item.copy }}</p>
        </article>
      </div>
    </section>

    <section :class="bemm('callout')">
      <p :class="bemm('eyebrow')">Scope</p>
      <h2 :class="bemm('heading')">Deliberately deferred</h2>
      <p :class="bemm('callout-copy')">AI upscaling and model runtime work are outside the current architecture and roadmap. ImageKid is not a nonlinear video editor, photo catalogue, collaboration service, or cloud product.</p>
    </section>
  </div>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";
import ProductPreview from "../components/ProductPreview";

const bemm = useBemm("features-page", { includeBaseClass: true });
const currentFeatures = [
  { title: "Open and view", copy: "Open by file panel, drag and drop, URL paste, or image paste. Fit, pan, pinch zoom, and reset the viewer." },
  { title: "Inspect colour", copy: "Sample image pixels, keep picked colours, copy values in useful formats, and export a local palette file." },
  { title: "Crop and resize", copy: "Use free crop, ratio presets, handles, guides, pixel dimensions, exact sizing, percentages, and scale presets." },
  { title: "Annotate", copy: "Add editable rectangles, ellipses, lines, arrows, freehand strokes, and text with contextual controls." },
  { title: "Export", copy: "Render PNG, JPEG, HEIC, TIFF, BMP, and GIF from the full-resolution source image and edit state." },
  { title: "Video playback", copy: "Play supported local video through AVFoundation. Editing and export are not available yet." }
];
const incompleteFeatures = [
  { title: "Colour analysis", copy: "Pixel-grid colour loupe and dominant palette extraction." },
  { title: "Advanced annotation", copy: "Blur, pixelation, annotation ordering, duplication, and rotation." },
  { title: "Document lifecycle", copy: "Undo, redo, dirty-close protection, recovery, and complete lifecycle behavior." },
  { title: "Media fidelity", copy: "Metadata preservation, advanced colour-profile controls, and complete video workflows." },
  { title: "Production release", copy: "Signing, sandbox entitlements, notarisation, packaging, and App Store distribution." }
];
</script>
