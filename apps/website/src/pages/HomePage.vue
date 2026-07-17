<template>
  <div :class="bemm()">
    <section :class="bemm('hero')">
      <div :class="bemm('hero-copy')">
        <p :class="bemm('eyebrow')">Native image tools for Mac</p>
        <h1 :class="bemm('title')">Local image editing without surprise costs.</h1>
        <p :class="bemm('lead')">Open images, remove backgrounds, upscale, crop, annotate, batch, and export on your Mac. Your files stay local unless you explicitly use Magic with your own AI provider.</p>
        <p :class="bemm('video-note')">Background removal and upscaling run locally. Magic uses your own provider subscription.</p>
        <div :class="bemm('actions')">
          <Button to="/features" variant="primary">Explore features</Button>
          <Button to="/privacy" variant="outline">Read privacy notes</Button>
        </div>
        <p :class="bemm('status')"><span>macOS 14+</span><span>App Store release planned</span><span>Local-first processing</span></p>
      </div>
      <ProductPreview />
    </section>

    <section :class="bemm('workflow')">
      <div :class="bemm('section-intro')">
        <p :class="bemm('eyebrow')">Local workflow</p>
        <h2 :class="bemm('heading')">From image to output, without an upload step.</h2>
        <p :class="bemm('section-copy')">The core tools run on your Mac, including background removal and high-quality upscaling.</p>
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

    <section :class="bemm('feature-index')">
      <div :class="bemm('section-intro')">
        <p :class="bemm('eyebrow')">Features</p>
        <h2 :class="bemm('heading')">All the image work in one place.</h2>
        <p :class="bemm('section-copy')">Jump into the details for each tool. Local tools stay local; Magic is the provider-backed exception.</p>
      </div>
      <div :class="bemm('feature-links')">
        <article v-for="feature in featureLinks" :key="feature.to" :class="bemm('feature-link')">
          <div :class="bemm('feature-link-copy')">
            <strong :class="bemm('feature-link-title')">{{ feature.title }}</strong>
            <span :class="bemm('feature-link-description')">{{ feature.description }}</span>
          </div>
          <Button :to="feature.to" variant="outline">{{ feature.action }}</Button>
        </article>
      </div>
    </section>

    <section :class="bemm('capabilities')">
      <div :class="bemm('section-intro')">
        <p :class="bemm('eyebrow')">Included locally</p>
        <h2 :class="bemm('heading')">The expensive stuff is not a service bill.</h2>
      </div>
      <div :class="bemm('capability-list')">
        <article v-for="capability in capabilities" :key="capability.title" :class="bemm('capability')">
          <span :class="bemm('capability-marker')" aria-hidden="true" />
          <h3 :class="bemm('capability-title')">{{ capability.title }}</h3>
          <p :class="bemm('capability-copy')">{{ capability.copy }}</p>
        </article>
      </div>
      <aside :class="bemm('limitation')">
        <strong>Magic is different</strong>
        <span>Prompted edits use your own AI provider key. Everything else stays local-first.</span>
      </aside>
    </section>

    <section :class="bemm('privacy')">
      <div :class="bemm('panel-copy')">
        <p :class="bemm('eyebrow')">Privacy</p>
        <h2 :class="bemm('heading')">No account required for local tools.</h2>
      </div>
      <p :class="bemm('panel-description')">Crop, resize, annotate, export, batch actions, background removal, and upscaling are designed to run on your Mac. Magic is the explicit exception and uses credentials you provide.</p>
    </section>

    <section :class="bemm('cta')">
      <div :class="bemm('panel-copy')">
        <p :class="bemm('eyebrow')">For Mac</p>
        <h2 :class="bemm('heading')">Built for a normal Mac app install.</h2>
        <p :class="bemm('cta-description')">The public release target is the App Store. The website should sell the app experience, not a build process.</p>
      </div>
      <Button to="/features" variant="primary">See the feature set</Button>
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
  { title: "Run local tools.", description: "Crop, resize, annotate, remove backgrounds, upscale, and batch without cloud processing." },
  { title: "Export deliberately.", description: "Choose an image format and render from the original image plus your edit state." }
];
const capabilities = [
  { title: "Remove backgrounds", copy: "One local action for cutting out subjects without paying for a hosted background-removal service." },
  { title: "Upscale locally", copy: "Enlarge images as much as your Mac can handle. No per-image fees and no remote processing." },
  { title: "Batch work", copy: "Apply repeated image actions to groups of files instead of clicking through each one." },
  { title: "Edit and export", copy: "Crop, resize, annotate, inspect colour, and export full-resolution image files." }
];
const featureLinks = [
  { title: "Pick colours", description: "Sample exact pixels and export palette values.", action: "Inspect", to: "/features#pick-colours" },
  { title: "Crop", description: "Use handles, ratios, guides, and exact dimensions.", action: "Crop", to: "/features#crop" },
  { title: "Resize", description: "Set precise output sizes and keep aspect ratios locked.", action: "Resize", to: "/features#resize" },
  { title: "Remove Background", description: "Cut out subjects locally without service credits.", action: "Remove", to: "/features#remove-background" },
  { title: "Upscale", description: "Create larger exports locally, without per-image fees.", action: "Upscale", to: "/features#upscale" },
  { title: "Batch actions", description: "Apply repeated work across groups of images.", action: "Batch", to: "/features#batch" },
  { title: "Annotate", description: "Add shapes, arrows, freehand marks, and text.", action: "Annotate", to: "/features#annotate" },
  { title: "Export", description: "Render deliberate outputs without overwriting originals.", action: "Export", to: "/features#export" },
  { title: "Magic", description: "Use prompted edits with your own AI provider.", action: "Magic", to: "/features#magic" }
];
</script>
