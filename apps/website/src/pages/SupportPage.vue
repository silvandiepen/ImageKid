<template>
  <div :class="bemm()">
    <p :class="bemm('eyebrow')">Support</p>
    <h1 :class="bemm('title')">Get help with ImageKid.</h1>
    <p :class="bemm('copy')">Include your macOS version, the image format, the action you used, and a concise description of what happened. Do not attach private media to public reports.</p>
    <div :class="bemm('contact-list')">
      <a :class="bemm('contact-link')" href="https://github.com/silvandiepen/imageKid/issues">
        <strong :class="bemm('contact-title')">GitHub Issues</strong>
        <span :class="bemm('contact-copy')">Report reproducible bugs and track technical discussion.</span>
      </a>
      <a :class="bemm('contact-link')" href="mailto:hello@hakobs.com">
        <strong :class="bemm('contact-title')">hello@hakobs.com</strong>
        <span :class="bemm('contact-copy')">Ask a support or privacy question by email.</span>
      </a>
    </div>
    <h2 :class="bemm('heading')">Local tools</h2>
    <p :class="bemm('copy')">Crop, resize, annotate, export, batch work, background removal, and upscaling are local-first. Magic is the explicit provider-backed feature and depends on your own AI provider credentials.</p>
    <p :class="bemm('last-updated')">Last updated: 17 Jul 2026</p>
  </div>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";

const bemm = useBemm("support-page", { includeBaseClass: true });
</script>
