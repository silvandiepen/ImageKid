<template>
  <div :class="bemm()">
    <p :class="bemm('eyebrow')">Privacy</p>
    <h1 :class="bemm('title')">Your media stays on your Mac.</h1>
    <h2 :class="bemm('heading')">The ImageKid app</h2>
    <p :class="bemm('copy')">ImageKid processes media locally. The app has no account, cloud processing, analytics, advertising, remote telemetry, paid API, or runtime download. It does not upload media, palettes, metadata, diagnostics, or usage information. Clipboard content is read only after an explicit paste action.</p>
    <h2 :class="bemm('heading')">This website</h2>
    <p :class="bemm('copy')">This website is a static site served by Cloudflare. When you visit, Cloudflare may process standard network request metadata such as IP address, user agent, requested URL, timestamps, and security signals to deliver and protect the site. The ImageKid project does not add website analytics or advertising trackers.</p>
    <h2 :class="bemm('heading')">Contact</h2>
    <p :class="bemm('copy')">For a privacy question, email <a :class="bemm('link')" href="mailto:hello@hakobs.com">hello@hakobs.com</a> or use <a :class="bemm('link')" href="https://github.com/silvandiepen/imageKid/issues">GitHub Issues</a>. Do not attach private media to a public issue.</p>
    <p :class="bemm('last-updated')">Last updated: 16 Jul 2026</p>
  </div>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";

const bemm = useBemm("privacy-page", { includeBaseClass: true });
</script>
