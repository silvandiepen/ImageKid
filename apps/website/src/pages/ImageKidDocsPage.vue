<template>
  <DocsShell>
    <div :class="bemm()">
      <header :class="bemm('header')">
        <img :class="bemm('icon')" src="/media/brand/imagekid.png" alt="" width="72" height="72" />
        <div>
          <p :class="bemm('eyebrow')">ImageKid documentation</p>
          <h1 :class="bemm('title')">Everything ImageKid does.</h1>
        </div>
      </header>

      <p :class="bemm('lede')">A native Mac image editor. Backgrounds, upscaling, crop, annotation and export all run on your Mac. Magic is the one workflow that talks to an AI provider, and only with a key you supply.</p>

      <figure :class="bemm('figure')">
        <img :class="bemm('shot')" src="/media/app/home.jpg" alt="The ImageKid home screen, with action cards and recent files." loading="lazy" />
        <figcaption :class="bemm('caption')">The home screen. Open an image, start a blank canvas, or pick up a recent file.</figcaption>
      </figure>

      <h2 :class="bemm('heading')">How to: cut out a subject</h2>
      <ol :class="bemm('steps')">
        <li>Open the image — drop it on the window, <kbd>⌘O</kbd>, or <kbd>⌘V</kbd> to paste.</li>
        <li>Run background removal. The built-in model is instant.</li>
        <li>If the edges are hard — hair, fur, a busy background — take the offer to download the best-quality model. It also runs on your Mac.</li>
        <li>Refine the mask by hand where you disagree with it. <kbd>⌘I</kbd> inverts if you wanted the background instead.</li>
        <li>Export as PNG to keep the transparency.</li>
      </ol>

      <h2 :class="bemm('heading')">How to: make a small image bigger</h2>
      <ol :class="bemm('steps')">
        <li>Open the image and go to Enhance.</li>
        <li>Pick a grade: Quick for an instant sharpen, High or Max for on-device AI detail.</li>
        <li>Choose the size — same, 2× or 4×.</li>
        <li>Apply, then export. Nothing was uploaded at any point.</li>
      </ol>

      <h2 :class="bemm('heading')">How to: crop without losing anything</h2>
      <ol :class="bemm('steps')">
        <li>Pick the crop tool. Drag the handles, or set a fixed ratio.</li>
        <li>Leave <em>Delete content outside crop</em> unticked and the crop stays reversible — the pixels are still there.</li>
        <li>Need a bigger frame rather than a smaller picture? That is Canvas Size, <kbd>⌥⌘C</kbd>.</li>
      </ol>

      <h2 :class="bemm('heading')">Getting an image in</h2>
      <p :class="bemm('copy')">Four ways, all equivalent: drop a file anywhere on the window, press <kbd>⌘O</kbd>, paste with <kbd>⌘V</kbd>, or drop a file onto the Dock icon. ImageKid opens JPEG, PNG, WebP, HEIC and TIFF. Nothing is written back to your original file unless you explicitly export over it.</p>

      <h2 :class="bemm('heading')">The workspace</h2>
      <figure :class="bemm('figure')">
        <img :class="bemm('shot')" src="/media/app/workspace.jpg" alt="ImageKid's workspace with the Files and Layers panels open beside the canvas." loading="lazy" />
        <figcaption :class="bemm('caption')">Files and Layers are floating panels — drag them anywhere, or dock them to an edge.</figcaption>
      </figure>
      <p :class="bemm('copy')">Every open image is a workspace item, listed in the Files panel. Panels float above the canvas and remember where you put them. Zoom with <kbd>⌘+</kbd> and <kbd>⌘-</kbd>, snap back with <kbd>⌘0</kbd> for actual size or <kbd>⇧⌘0</kbd> to fit the window.</p>

      <h2 :class="bemm('heading')">Removing a background</h2>
      <figure :class="bemm('figure')">
        <img :class="bemm('shot')" src="/media/app/background.jpg" alt="Background removal applied to a photograph in ImageKid." loading="lazy" />
      </figure>
      <p :class="bemm('copy')">Runs a Core ML segmentation model on your Mac — no upload, no account. The result is a mask, not a destructive edit, so you can refine the edge afterwards or invert it with <kbd>⌘I</kbd>. The first run may offer to download a higher-quality model; declining keeps the faster built-in one.</p>

      <h2 :class="bemm('heading')">Cropping and resizing</h2>
      <figure :class="bemm('figure')">
        <img :class="bemm('shot')" src="/media/app/crop.jpg" alt="ImageKid's crop panel with a 16:9 ratio and rule-of-thirds grid." loading="lazy" />
      </figure>
      <p :class="bemm('copy')">Crop offers free-form or fixed ratios with a rule-of-thirds grid. Content outside the crop is kept by default so the crop stays reversible; tick <em>Delete content outside crop</em> to commit it. Canvas size is separate — <kbd>⌥⌘C</kbd> changes the frame without scaling the image.</p>

      <h2 :class="bemm('heading')">Annotating</h2>
      <figure :class="bemm('figure')">
        <img :class="bemm('shot')" src="/media/app/annotate.jpg" alt="Annotation tools in ImageKid." loading="lazy" />
      </figure>
      <p :class="bemm('copy')">Shapes, arrows and text sit on their own layer above the image. Reorder them with <kbd>⌘]</kbd> and <kbd>⌘[</kbd>, or send them to the extremes with <kbd>⇧⌘]</kbd> and <kbd>⇧⌘[</kbd>. <kbd>⎋</kbd> cancels whatever tool is active.</p>

      <h2 :class="bemm('heading')">Sampling colour</h2>
      <figure :class="bemm('figure')">
        <img :class="bemm('shot')" src="/media/app/color.jpg" alt="The colour picker sampling colours from an image." loading="lazy" />
      </figure>
      <p :class="bemm('copy')">Pick colours straight off the canvas and keep them in a swatch list. Useful for matching an annotation to something already in the frame.</p>

      <h2 :class="bemm('heading')">Magic</h2>
      <figure :class="bemm('figure')">
        <img :class="bemm('shot')" src="/media/app/magic.jpg" alt="The Magic prompt sheet in ImageKid." loading="lazy" />
      </figure>
      <p :class="bemm('copy')">Prompted editing through an AI provider. This is the only feature that leaves your Mac, it never runs unless you ask it to, and it needs a provider key you add yourself in Settings. Billing and rate limits come from that provider account.</p>

      <h2 :class="bemm('heading')">Exporting</h2>
      <figure :class="bemm('figure')">
        <img :class="bemm('shot')" src="/media/app/export.jpg" alt="ImageKid's export sheet with format and size options." loading="lazy" />
      </figure>
      <p :class="bemm('copy')">Choose format, quality and size. With several items selected, export processes the whole set in one pass.</p>

      <h2 :class="bemm('heading')">Keyboard shortcuts</h2>
      <p :class="bemm('copy')">Generated from the app's own menu definitions, so this list matches what ships.</p>
      <ShortcutTable :sections="shortcuts.ImageKid" />
    </div>
  </DocsShell>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";
import DocsShell from "../components/DocsShell";
import ShortcutTable from "../components/ShortcutTable.vue";
import { shortcuts } from "../data/shortcuts";

const bemm = useBemm("imagekid-docs-page", { includeBaseClass: true });
</script>

<style lang="scss">
.imagekid-docs-page,
.fekthor-docs-page {
  &__header {
    display: flex;
    align-items: center;
    gap: var(--space-l);
    margin-bottom: var(--space-l);
  }

  // The exported app icons already carry their own squircle and shadow.
  // Any radius, border or shadow here double-clips them.
  &__icon { width: 72px; height: 72px; }

  &__lede { font-size: var(--font-size-l); line-height: 1.5; }

  &__figure {
    margin: var(--space-xl) 0;
    display: grid;
    gap: var(--space-s);
  }

  &__shot {
    width: 100%;
    height: auto;
    border-radius: var(--border-radius-l);
    border: var(--border-width) solid
      color-mix(in srgb, var(--color-foreground), transparent 88%);
  }

  &__caption { font-size: var(--font-size-s); opacity: 0.65; }

  &__steps {
    margin-top: var(--space-m);
    display: grid;
    gap: var(--space-m);
    padding-inline-start: var(--space-xl);

    li { padding-inline-start: var(--space-xs); }
    li::marker { color: var(--color-primary); font-weight: 700; }
  }

  &__heading { margin-top: var(--space-xxl); }
  &__copy { margin-top: var(--space-m); }
}
</style>
