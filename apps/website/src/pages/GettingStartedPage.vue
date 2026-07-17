<template>
  <DocsShell>
    <div :class="bemm()">
      <p :class="bemm('eyebrow')">Getting started</p>
      <h1 :class="bemm('title')">Start with a local image.</h1>
      <aside :class="bemm('note')">
        <strong :class="bemm('note-title')">Local by default</strong>
        <span :class="bemm('note-copy')">ImageKid keeps the everyday tools on your Mac. Magic is the only workflow that uses an AI provider account you connect.</span>
      </aside>
      <h2 :class="bemm('heading')">Requirements</h2>
      <ul :class="bemm('list')">
        <li :class="bemm('list-item')">macOS 14 or newer</li>
        <li :class="bemm('list-item')">A local image file, pasted image, or image URL</li>
        <li :class="bemm('list-item')">An optional AI provider key only when using Magic</li>
      </ul>
      <h2 :class="bemm('heading')">Open media</h2>
      <p :class="bemm('copy')">Drag a supported local file into the window, use File › Open or Command-O, or paste an image with Command-V.</p>
      <h2 :class="bemm('heading')">Use local tools</h2>
      <p :class="bemm('copy')">Crop, resize, annotate, remove backgrounds, upscale, batch, and export without uploading the image for those operations.</p>
      <h2 :class="bemm('heading')">Use Magic</h2>
      <p :class="bemm('copy')">Connect a provider key only when you want prompted image editing. Provider billing and subscription limits come from the provider account you choose.</p>
      <Button to="/features" variant="primary">View features</Button>
    </div>
  </DocsShell>
</template>

<script setup lang="ts">
import { Button } from "@sil/ui";
import { useBemm } from "bemm";
import DocsShell from "../components/DocsShell";

const bemm = useBemm("getting-started-page", { includeBaseClass: true });
</script>
