<template>
  <div :class="bemm()">
    <section :class="bemm('hero')">
      <div :class="bemm('hero-copy')">
        <p :class="bemm('eyebrow')">Native, local-first apps for Mac</p>
        <h1 :class="bemm('title')">Image tools that run on your Mac.</h1>
        <p :class="bemm('lead')">Four native apps for images and vectors. No accounts, no subscriptions, no upload step. Your pictures stay where they are.</p>
        <p :class="bemm('video-note')">Everything heavy happens on your Mac. Magic is the one exception, and it only runs on your own provider key.</p>
        <div :class="bemm('actions')">
          <Button to="/#apps" variant="primary">Explore the apps</Button>
          <Button to="/imagekid" variant="outline">Meet ImageKid</Button>
        </div>
        <p :class="bemm('status')"><span>macOS 14+</span><span>iPad &amp; iPhone</span><span>Local-first processing</span></p>
      </div>
      <AppHero
        character="/media/character/imagekid.png"
        screenshot="/media/app/workspace.jpg"
        variant="imagekid"
      />
    </section>

    <section id="apps" :class="bemm('apps')">
      <div :class="bemm('section-intro')">
        <p :class="bemm('eyebrow')">The apps</p>
        <h2 :class="bemm('heading')">Four apps. One stubborn principle.</h2>
        <p :class="bemm('section-copy')">All four run on the same on-device engine. Take the full editor, a focused batch tool, or the vector one.</p>
      </div>
      <div :class="bemm('app-grid')">
        <RouterLink
          v-for="app in apps"
          :key="app.id"
          :class="bemm('app-card', [app.flagship ? 'flagship' : '', app.id])"
          :to="app.to"
        >
          <img :class="bemm('app-icon')" :src="app.icon" :alt="`${app.name} app icon`" width="56" height="56" />
          <div :class="bemm('app-copy')">
            <span :class="bemm('app-name')">{{ app.name }}</span>
            <span :class="bemm('app-tagline')">{{ app.tagline }}</span>
            <span :class="bemm('app-summary')">{{ app.summary }}</span>
          </div>
          <span :class="bemm('app-meta')"><span>{{ app.platforms }}</span><span :class="bemm('app-status')">{{ app.status }}</span></span>
        </RouterLink>
      </div>
    </section>

    <section :class="bemm('showcase', 'imagekid')">
      <figure :class="bemm('showcase-media')">
        <img :class="bemm('showcase-image')" src="/media/app/workspace.jpg" alt="The ImageKid editor with an image open" />
      </figure>
      <div :class="bemm('showcase-copy')">
        <div :class="bemm('showcase-brand')">
          <img :src="imagekid.icon" :alt="''" width="40" height="40" />
          <p :class="bemm('eyebrow')">Flagship · {{ imagekid.platforms }}</p>
        </div>
        <h2 :class="bemm('heading')">ImageKid — the complete editor.</h2>
        <p :class="bemm('section-copy')">{{ imagekid.summary }} Remove backgrounds, enhance with quality grades, crop, annotate, and export — all on device.</p>
        <ul :class="bemm('showcase-list')">
          <li v-for="point in imagekidPoints" :key="point">{{ point }}</li>
        </ul>
        <Button to="/imagekid" variant="primary">Explore ImageKid</Button>
      </div>
    </section>

    <section :class="bemm('showcase', 'fekthor')">
      <div :class="bemm('showcase-copy')">
        <div :class="bemm('showcase-brand')">
          <img :src="fekthor.icon" :alt="''" width="40" height="40" />
          <p :class="bemm('eyebrow')">Flagship · {{ fekthor.platforms }}</p>
        </div>
        <h2 :class="bemm('heading')">Fekthor — vectors, built for icon sets.</h2>
        <p :class="bemm('section-copy')">Draw and trace real vectors, then keep a whole folder of icons in step — one colour change, two hundred icons updated. Plain SVG out.</p>
        <ul :class="bemm('showcase-list')">
          <li v-for="point in fekthorPoints" :key="point">{{ point }}</li>
        </ul>
        <Button to="/fekthor" variant="primary">Meet Fekthor</Button>
      </div>
      <div :class="bemm('showcase-panel')" aria-hidden="true">
        <img :class="bemm('showcase-panel-icon')" :src="fekthor.icon" :alt="''" width="140" height="140" />
      </div>
    </section>

    <section :class="bemm('privacy')">
      <div :class="bemm('panel-copy')">
        <p :class="bemm('eyebrow')">Privacy</p>
        <h2 :class="bemm('heading')">No account required for local tools.</h2>
      </div>
      <p :class="bemm('panel-description')">Editing, background removal, upscaling, batch work, and vector tracing are designed to run on your device. Magic is the explicit exception and uses credentials you provide.</p>
    </section>

    <section :class="bemm('cta')">
      <div :class="bemm('panel-copy')">
        <p :class="bemm('eyebrow')">For Mac</p>
        <h2 :class="bemm('heading')">Built for a normal app install.</h2>
        <p :class="bemm('cta-description')">Native apps you buy once and run locally — no subscriptions, no credits, no lock-in.</p>
      </div>
      <Button to="/#apps" variant="primary">See the apps</Button>
    </section>
  </div>
</template>

<script setup lang="ts">
import { Button } from "@sil/ui";
import { useBemm } from "bemm";
import { RouterLink } from "vue-router";
import AppHero from "../components/AppHero";
import { apps, appById } from "../data/apps";

const bemm = useBemm("home-page", { includeBaseClass: true });
const imagekid = appById("imagekid")!;
const fekthor = appById("fekthor")!;
const imagekidPoints = [
  "One-tap background removal, built-in and best-quality",
  "Enhance & upscale with Quick · High · Max grades",
  "Crop, resize, rotate, annotate, and export locally"
];
const fekthorPoints = [
  "Trace raster art into editable centreline strokes",
  "Folder-backed workspace for whole icon sets",
  "Design tokens and non-destructive export profiles"
];
</script>
