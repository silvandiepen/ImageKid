<template>
  <div :class="bemm()">
    <p :class="bemm('eyebrow')">Support</p>
    <h1 :class="bemm('title')">Get help with ImageKid.</h1>
    <p :class="bemm('copy')">ImageKid is early-stage source software. Include your macOS version, Xcode version, the command or workflow you used, and a concise description of what happened.</p>
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
    <h2 :class="bemm('heading')">Before reporting a build issue</h2>
    <pre :class="bemm('code-block')"><code :class="bemm('code')">cd apps/native-macos
swift build
swift test</code></pre>
    <p :class="bemm('copy')">The Swift package requires macOS frameworks and cannot be built on Linux. There is no packaged, notarised, or App Store release at this stage.</p>
    <p :class="bemm('last-updated')">Last updated: 16 Jul 2026</p>
  </div>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";

const bemm = useBemm("support-page", { includeBaseClass: true });
</script>
