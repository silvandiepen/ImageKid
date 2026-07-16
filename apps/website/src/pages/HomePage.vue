<template>
  <div :class="bemm()">
    <section :class="bemm('hero')">
      <div :class="bemm('hero-copy')">
        <p :class="bemm('eyebrow')">Native image tools for Mac</p>
        <h1 :class="bemm('title')">Inspect, edit, and export images on your Mac.</h1>
        <p :class="bemm('lead')">Open an image, inspect exact colours, make a focused edit, and export a full-resolution result. Basic local video playback is available separately. Your files stay on your Mac.</p>
        <div :class="bemm('actions')">
          <Button to="/docs/getting-started" variant="primary">Build from source</Button>
          <Button to="/features" variant="outline">See current features</Button>
        </div>
        <p :class="bemm('status')">Early-stage source build for macOS 14+. No packaged download is available yet.</p>
      </div>
      <ProductPreview />
    </section>

    <section :class="bemm('workflow')">
      <div :class="bemm('section-intro')">
        <p :class="bemm('eyebrow')">One focused image workflow</p>
        <h2 :class="bemm('heading')">From local image to useful output.</h2>
      </div>
      <ol :class="bemm('steps')">
        <li :class="bemm('step')">
          <div :class="bemm('step-copy')">
            <strong :class="bemm('step-title')">Open directly.</strong>
            <span :class="bemm('step-description')">Drop an image, paste one, or use File › Open.</span>
          </div>
        </li>
        <li :class="bemm('step')">
          <div :class="bemm('step-copy')">
            <strong :class="bemm('step-title')">Edit the image.</strong>
            <span :class="bemm('step-description')">Fit, pan, zoom, sample pixels, crop, resize, or annotate without a permanent editor sidebar.</span>
          </div>
        </li>
        <li :class="bemm('step')">
          <div :class="bemm('step-copy')">
            <strong :class="bemm('step-title')">Export deliberately.</strong>
            <span :class="bemm('step-description')">Choose an image format and render from the original image plus your edit state.</span>
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
        <div :class="bemm('capability')">
          <h3 :class="bemm('capability-title')">View and inspect</h3>
          <p :class="bemm('capability-copy')">Fitted viewing, mouse and trackpad pan, pinch zoom, pixel colour sampling, saved colour values, and palette file export.</p>
        </div>
        <div :class="bemm('capability')">
          <h3 :class="bemm('capability-title')">Crop and resize</h3>
          <p :class="bemm('capability-copy')">Free crop, ratio choices, handles, pixel dimensions, exact sizing, percentages, and scale presets.</p>
        </div>
        <div :class="bemm('capability')">
          <h3 :class="bemm('capability-title')">Annotate</h3>
          <p :class="bemm('capability-copy')">Editable rectangles, ellipses, lines, arrows, freehand strokes, and text with contextual controls.</p>
        </div>
        <div :class="bemm('capability')">
          <h3 :class="bemm('capability-title')">Export images</h3>
          <p :class="bemm('capability-copy')">PNG, JPEG, HEIC, TIFF, BMP, and GIF output with format controls. Exports are rendered at full resolution.</p>
        </div>
      </div>
      <p :class="bemm('limitation')">Video support is currently basic local playback only. Video editing and export are planned, not implemented.</p>
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
        <h2 :class="bemm('heading')">Build the native foundation.</h2>
        <p :class="bemm('cta-description')">The source package builds on macOS with Xcode 16 and Swift 5.10. Signing, sandboxing, notarisation, and App Store packaging remain future release work.</p>
      </div>
      <Button to="/docs/getting-started" variant="primary">Read build guide</Button>
    </section>
  </div>
</template>

<script setup lang="ts">
import { Button } from "@sil/ui";
import { useBemm } from "bemm";
import ProductPreview from "../components/ProductPreview";

const bemm = useBemm("home-page", { includeBaseClass: true });
</script>
