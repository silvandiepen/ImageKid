<template>
  <div :class="bemm()">
    <p :class="bemm('eyebrow')">Privacy</p>
    <h1 :class="bemm('title')">Your media stays on your Mac.</h1>
    <h2 :class="bemm('heading')">The ImageKid app</h2>
    <p :class="bemm('copy')">ImageKid processes the core image workflow locally: crop, resize, annotate, export, batches, background removal, and upscaling run on your Mac. The app does not upload media for those tools, and there are no per-image service fees for them.</p>
    <h2 :class="bemm('heading')">Magic</h2>
    <p :class="bemm('copy')">Magic is the explicit exception. Prompted edits can call an AI provider using credentials you supply. Provider usage, billing, and retention are governed by your provider account and settings.</p>
    <h2 :class="bemm('heading')">This website</h2>
    <p :class="bemm('copy')">This website is a static site served by Cloudflare. When you visit, Cloudflare may process standard network request metadata such as IP address, user agent, requested URL, timestamps, and security signals to deliver and protect the site. The ImageKid project does not add website analytics or advertising trackers.</p>
    <h2 :class="bemm('heading')">Contact</h2>
    <p :class="bemm('copy')">For a privacy question, email <a :class="bemm('link')" href="mailto:hello@hakobs.com">hello@hakobs.com</a> or use <a :class="bemm('link')" href="https://github.com/silvandiepen/imageKid/issues">GitHub Issues</a>. Do not attach private media to a public issue.</p>
    <p :class="bemm('last-updated')">Last updated: 17 Jul 2026</p>
  </div>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";

const bemm = useBemm("privacy-page", { includeBaseClass: true });
</script>
