<template>
  <div :class="bemm()">
    <section :class="bemm('hero')">
      <div :class="bemm('hero-copy')">
        <p :class="bemm('eyebrow')">Native image tools for Mac</p>
        <h1 :class="bemm('title')">Inspect, edit, and export images on your Mac.</h1>
        <p :class="bemm('lead')">Open an image, inspect exact colours, make a focused edit, and export a full-resolution result — without sending the file anywhere.</p>
        <p :class="bemm('video-note')">Video support is currently limited to local playback.</p>
        <div :class="bemm('actions')">
          <Button to="/docs/getting-started" variant="primary">Build from source</Button>
          <Button to="/features" variant="outline">Explore current features</Button>
        </div>
        <p :class="bemm('status')"><span>Source build</span><span>macOS 14+</span><span>No packaged release</span></p>
      </div>
      <ProductPreview />
    </section>

    <section :class="bemm('workflow')">
      <div :class="bemm('section-intro')">
        <p :class="bemm('eyebrow')">One focused image workflow</p>
        <h2 :class="bemm('heading')">From local image to useful output.</h2>
        <p :class="bemm('section-copy')">The tools appear when they matter and stay out of the way when they do not.</p>
      </div>
      <ol :class="bemm('steps')">
        <li v-for="(step, index) in steps" :key="step.title" :class="bemm('step')">
          <span :class="bemm('step-number')">0{{ index + 1 }}</span>
          <div :class="bemm('step-copy')">
            <strong :class="bemm('step-title')">{{ step.title }}</strong>
            <span :class="bemm('step-description')">{{ step.description }}</span>
          </div>
        </li>
      </ol>
    </section>

    <section :class="bemm('capabilities')">
      <div :class="bemm('section-intro')">
        <p :class="bemm('eyebrow')">In the current build</p>
        <h2 :class="bemm('heading')">Small image tasks, together.</h2>
      </div>
      <div :class="bemm('capability-list')">
        <article v-for="capability in capabilities" :key="capability.title" :class="bemm('capability')">
          <span :class="bemm('capability-marker')" aria-hidden="true" />
          <h3 :class="bemm('capability-title')">{{ capability.title }}</h3>
          <p :class="bemm('capability-copy')">{{ capability.copy }}</p>
        </article>
      </div>
      <aside :class="bemm('limitation')">
        <strong>Playback only</strong>
        <span>Video editing and export are planned, not implemented.</span>
      </aside>
    </section>

    <section :class="bemm('privacy')">
      <div :class="bemm('panel-copy')">
        <p :class="bemm('eyebrow')">Local by design</p>
        <h2 :class="bemm('heading')">No upload step. No account.</h2>
      </div>
      <p :class="bemm('panel-description')">ImageKid does not use cloud processing, analytics, ads, paid APIs, runtime downloads, or remote activation. Media processing happens on your Mac.</p>
    </section>

    <section :class="bemm('cta')">
      <div :class="bemm('panel-copy')">
        <p :class="bemm('eyebrow')">Current status</p>
        <h2 :class="bemm('heading')">Run the current native build.</h2>
        <p :class="bemm('cta-description')">Build the Swift package on macOS with Xcode 16 and Swift 5.10. It is not signed, sandboxed, notarised, or packaged for distribution.</p>
      </div>
      <Button to="/docs/getting-started" variant="primary">Read the build guide</Button>
    </section>
  </div>
</template>

<script setup lang="ts">
import { Button } from "@sil/ui";
import { useBemm } from "bemm";
import ProductPreview from "../components/ProductPreview";

const bemm = useBemm("home-page", { includeBaseClass: true });
const steps = [
  { title: "Open directly.", description: "Drop an image, paste one, or use File › Open." },
  { title: "Edit the image.", description: "Pan, zoom, sample pixels, crop, resize, or annotate without a permanent editor sidebar." },
  { title: "Export deliberately.", description: "Choose an image format and render from the original image plus your edit state." }
];
const capabilities = [
  { title: "View and inspect", copy: "Fitted viewing, pan, pinch zoom, pixel colour sampling, saved colour values, and palette export." },
  { title: "Crop and resize", copy: "Free crop, ratio choices, handles, pixel dimensions, exact sizing, percentages, and scale presets." },
  { title: "Annotate", copy: "Editable rectangles, ellipses, lines, arrows, freehand strokes, and text with contextual controls." },
  { title: "Export images", copy: "PNG, JPEG, HEIC, TIFF, BMP, and GIF output rendered from the full-resolution image." }
];
</script>
