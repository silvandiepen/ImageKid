<template>
  <div :class="bemm()">
    <header :class="bemm('hero')">
      <div :class="bemm('hero-copy')">
        <p :class="bemm('eyebrow')">Features</p>
        <h1 :class="bemm('title')">Local image tools that do not meter every edit.</h1>
        <p :class="bemm('lead')">Remove backgrounds, upscale, crop, annotate, batch, and export on your Mac. Magic can call your own AI provider, but the core image tools stay local.</p>
        <p :class="bemm('status')">No upload step for local tools. No per-image fees for background removal or upscaling.</p>
      </div>
      <figure :class="bemm('hero-media')">
        <video
          :class="bemm('video')"
          src="/media/app/annotate-workflow.mp4"
          poster="/media/app/workspace.jpg"
          autoplay
          muted
          loop
          playsinline
          controls
        />
        <figcaption :class="bemm('caption')">A captured ImageKid workflow using the example image.</figcaption>
      </figure>
    </header>

    <section :class="bemm('workflow')">
      <div :class="bemm('section-heading')">
        <p :class="bemm('eyebrow')">Workflow</p>
        <h2 :class="bemm('heading')">One Mac app for repeat image work.</h2>
        <p :class="bemm('section-copy')">ImageKid is built around direct local actions: open an image, make the edit, apply the same kind of work in batches, and export without handing the file to a web service.</p>
      </div>
      <figure :class="bemm('wide-shot')">
        <img :class="bemm('image')" src="/media/app/workspace.jpg" alt="ImageKid workspace with an image open and the tool menu visible." width="2000" height="1256" decoding="async" />
      </figure>
    </section>

    <section
      v-for="feature in featureSections"
      :id="feature.id"
      :key="feature.id"
      :class="[bemm('feature-band'), bemm('feature-band', feature.tone), feature.imageSide === 'left' ? bemm('feature-band', 'image-left') : '']"
    >
      <div :class="bemm('feature-inner')">
        <div :class="bemm('feature-copy')">
          <p :class="bemm('eyebrow')">{{ feature.eyebrow }}</p>
          <h2 :class="bemm('heading')">{{ feature.title }}</h2>
          <p :class="bemm('section-copy')">{{ feature.copy }}</p>
          <p v-if="feature.disclaimer" :class="bemm('disclaimer')">{{ feature.disclaimer }}</p>
        </div>
        <figure :class="bemm('feature-media')">
          <img :class="bemm('image')" :src="feature.image" :alt="feature.alt" loading="lazy" decoding="async" />
        </figure>
      </div>
    </section>

    <section :class="bemm('section')">
      <div :class="bemm('section-heading')">
        <p :class="bemm('eyebrow')">Scope</p>
        <h2 :class="bemm('heading')">Clear boundaries, not hidden subscriptions.</h2>
      </div>
      <div :class="bemm('boundary-grid')">
        <article v-for="item in boundaryItems" :key="item.title" :class="bemm('boundary-item')">
          <Icon :class="bemm('boundary-icon')" :name="item.icon" size="large" aria-hidden="true" />
          <h3 :class="bemm('boundary-title')">{{ item.title }}</h3>
          <p :class="bemm('boundary-copy')">{{ item.copy }}</p>
        </article>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import { Icon } from "@sil/ui";
import { useBemm } from "bemm";

const bemm = useBemm("features-page", { includeBaseClass: true });
const featureSections = [
  {
    id: "pick-colours",
    title: "Pick exact colours",
    eyebrow: "Inspect",
    copy: "Sample image pixels, keep picked colours, copy useful values, and export a local palette file.",
    image: "/media/app/color-picker.jpg",
    alt: "ImageKid colour picker panel with sampled colours from the open image.",
    tone: "tone-1",
    imageSide: "right"
  },
  {
    id: "crop",
    title: "Crop from the image",
    eyebrow: "Crop",
    copy: "Use free crop, ratio presets, handles, rule-of-thirds guides, editable pixel dimensions, reset, cancel, and apply.",
    image: "/media/app/crop.jpg",
    alt: "ImageKid crop overlay around part of the example image.",
    tone: "tone-2",
    imageSide: "left"
  },
  {
    id: "resize",
    title: "Resize deliberately",
    eyebrow: "Resize",
    copy: "Set exact output sizes, percentage presets, aspect lock, and an explicit apply or cancel step.",
    image: "/media/app/resize.jpg",
    alt: "ImageKid resize tool showing output frame and size controls.",
    tone: "tone-3",
    imageSide: "right"
  },
  {
    id: "remove-background",
    title: "Remove Background",
    eyebrow: "Local and included",
    copy: "Cut out the subject with a direct local action. No remote background-removal credits and no hosted cutout service.",
    disclaimer: "For best quality, enable or install the advanced background feature in Settings. It is still local and free.",
    image: "/media/app/workspace.jpg",
    alt: "ImageKid workspace with the example image open.",
    tone: "tone-4",
    imageSide: "left"
  },
  {
    id: "upscale",
    title: "Upscale locally",
    eyebrow: "Local and included",
    copy: "Create larger exports with local upscaling instead of paying a hosted service per image. Upscale as much as your Mac can reasonably process.",
    disclaimer: "For best quality, enable or install the advanced upscaling feature in Settings. It is still local and free.",
    image: "/media/app/export.jpg",
    alt: "ImageKid export sheet with upscaling and output options.",
    tone: "tone-5",
    imageSide: "right"
  },
  {
    id: "batch",
    title: "Batch actions",
    eyebrow: "Repeat work",
    copy: "Run repeated transforms across groups of images instead of clicking through the same work one file at a time.",
    image: "/media/app/workspace.jpg",
    alt: "ImageKid workspace ready for repeated local image actions.",
    tone: "tone-2",
    imageSide: "left"
  },
  {
    id: "annotate",
    title: "Annotate",
    eyebrow: "Mark up",
    copy: "Add editable rectangles, ellipses, lines, arrows, freehand strokes, and text with contextual controls.",
    image: "/media/app/annotate.jpg",
    alt: "ImageKid annotation tools with shapes and marks over the example image.",
    tone: "tone-1",
    imageSide: "right"
  },
  {
    id: "export",
    title: "Choose the output deliberately",
    eyebrow: "Export",
    copy: "Export renders PNG, JPEG, HEIC, TIFF, BMP, and GIF from the source media plus the current edit state. It does not overwrite the original file implicitly.",
    image: "/media/app/export.jpg",
    alt: "ImageKid export sheet with format and output options.",
    tone: "tone-3",
    imageSide: "left"
  },
  {
    id: "magic",
    title: "Magic uses your AI provider.",
    eyebrow: "Magic",
    copy: "Prompted edits are intentionally separate from the local tools. OpenAI is the first provider, you bring the provider key, and the app warns when credentials are missing.",
    image: "/media/app/magic-provider-warning.jpg",
    alt: "ImageKid Magic panel showing a missing provider key warning.",
    tone: "magic",
    imageSide: "right"
  }
];
const boundaryItems = [
  { title: "Local tools stay local", icon: "media/laptop", copy: "Crop, resize, annotate, export, background removal, upscaling, and batches are designed for on-device processing." },
  { title: "Magic uses your provider", icon: "misc/ai-stars", copy: "Prompted edits can use OpenAI first, with room for other providers later. That usage depends on your own provider account." },
  { title: "No implicit overwrites", icon: "ui/file-check", copy: "ImageKid exports a new result instead of silently replacing the source file." },
  { title: "Video is separate", icon: "media/video-camera", copy: "Video playback exists, while video editing and export remain outside the main image workflow." }
];
</script>
