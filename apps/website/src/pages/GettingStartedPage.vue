<template>
  <DocsShell>
    <div :class="bemm()">
      <p :class="bemm('eyebrow')">Getting started</p>
      <h1 :class="bemm('title')">Run the native app from source.</h1>
      <h2 :class="bemm('heading')">Requirements</h2>
      <ul :class="bemm('list')">
        <li :class="bemm('list-item')">macOS 14 or newer</li>
        <li :class="bemm('list-item')">Xcode 16 or newer with the macOS SDK</li>
        <li :class="bemm('list-item')">Swift 5.10 or newer</li>
      </ul>
      <h2 :class="bemm('heading')">Terminal</h2>
      <p :class="bemm('copy')">From the repository root:</p>
      <pre :class="bemm('code-block')"><code :class="bemm('code')">cd apps/native-macos
swift build
swift test
swift run ImageKid</code></pre>
      <p :class="bemm('copy')">Equivalent root helpers are <code :class="bemm('code')">npm run native:build</code>, <code :class="bemm('code')">npm run native:test</code>, and <code :class="bemm('code')">npm run native:run</code>.</p>
      <h2 :class="bemm('heading')">Xcode</h2>
      <p :class="bemm('copy')">Open <code :class="bemm('code')">apps/native-macos/Package.swift</code>, select the <code :class="bemm('code')">ImageKid</code> scheme, choose My Mac, and run.</p>
      <h2 :class="bemm('heading')">Open media</h2>
      <p :class="bemm('copy')">Drag a supported local file into the window, use File › Open or Command-O, or paste an image with Command-V.</p>
      <aside :class="bemm('note')">
        <strong :class="bemm('note-title')">Development boundary</strong>
        <span :class="bemm('note-copy')">A package build is not a signed app release. The repository does not yet provide production signing, sandboxing, notarisation, or App Store configuration.</span>
      </aside>
    </div>
  </DocsShell>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";
import DocsShell from "../components/DocsShell";

const bemm = useBemm("getting-started-page", { includeBaseClass: true });
</script>
