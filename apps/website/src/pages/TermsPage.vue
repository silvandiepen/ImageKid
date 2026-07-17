<template>
  <div :class="bemm()">
    <p :class="bemm('eyebrow')">Terms</p>
    <h1 :class="bemm('title')">Plain terms for ImageKid.</h1>
    <h2 :class="bemm('heading')">Local app</h2>
    <p :class="bemm('copy')">ImageKid is a native Mac image utility. Local tools run on your Mac; Magic is an explicit provider-backed feature that uses credentials you supply.</p>
    <h2 :class="bemm('heading')">Your files</h2>
    <p :class="bemm('copy')">You remain responsible for your media, backups, edits, exports, and rights to process the content you open. ImageKid is designed not to overwrite source files implicitly, but you should keep your own backups.</p>
    <h2 :class="bemm('heading')">No selected open-source licence</h2>
    <p :class="bemm('copy')">No open-source licence has been selected for this repository. Source availability is not permission to copy, modify, redistribute, sublicense, or reuse the code or assets. All rights remain reserved unless the rights holder grants permission separately.</p>
    <h2 :class="bemm('heading')">Liability</h2>
    <p :class="bemm('copy')">To the extent permitted by applicable law, the software and website are provided without warranties. The maintainers are not responsible for loss arising from use of this early-stage software.</p>
    <h2 :class="bemm('heading')">Contact</h2>
    <p :class="bemm('copy')">Questions can be sent to <a :class="bemm('link')" href="mailto:hello@hakobs.com">hello@hakobs.com</a> or raised through <a :class="bemm('link')" href="https://github.com/silvandiepen/imageKid/issues">GitHub Issues</a>.</p>
    <p :class="bemm('last-updated')">Last updated: 17 Jul 2026</p>
  </div>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";

const bemm = useBemm("terms-page", { includeBaseClass: true });
</script>
