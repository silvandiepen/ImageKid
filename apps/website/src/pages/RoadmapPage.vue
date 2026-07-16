<template>
  <DocsShell>
    <div :class="bemm()">
      <p :class="bemm('eyebrow')">Roadmap</p>
      <h1 :class="bemm('title')">Finish the core before expanding it.</h1>
      <h2 :class="bemm('heading')">Current foundation</h2>
      <p :class="bemm('copy')">Image viewing and inspection, crop and resize state, six editable annotation types, full-resolution image export, and basic local video playback are implemented in source.</p>
      <h2 :class="bemm('heading')">Next product work</h2>
      <ol :class="bemm('list')">
        <li :class="bemm('list-item')">Complete the pixel-grid loupe and dominant palette extraction.</li>
        <li :class="bemm('list-item')">Add blur, pixelation, annotation ordering, duplication, and rotation.</li>
        <li :class="bemm('list-item')">Implement undo, redo, dirty-close protection, and recovery.</li>
        <li :class="bemm('list-item')">Improve metadata, colour-profile, accessibility, and large-file handling.</li>
        <li :class="bemm('list-item')">Build video frame inspection, colour sampling, crop, resize, static time-ranged annotations, and local export as a separate technical slice.</li>
        <li :class="bemm('list-item')">Create the signed application target, sandbox entitlements, release assets, archive configuration, and distribution validation.</li>
      </ol>
      <h2 :class="bemm('heading')">Not on the current roadmap</h2>
      <p :class="bemm('copy')">AI upscaling is deferred. Multiple tracks, trimming, transitions, motion tracking, keyframes, audio editing, accounts, collaboration, sync, and batch processing are not first-release goals.</p>
    </div>
  </DocsShell>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";
import DocsShell from "../components/DocsShell";

const bemm = useBemm("roadmap-page", { includeBaseClass: true });
</script>
