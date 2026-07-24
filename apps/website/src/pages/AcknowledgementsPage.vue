<template>
  <div :class="bemm()">
    <p :class="bemm('eyebrow')">Acknowledgements</p>
    <h1 :class="bemm('title')">What we build on.</h1>
    <p :class="bemm('copy')">ImageKid and Fekthor are native Mac apps built on Apple's own frameworks. Beyond those, the apps bundle the components listed here. Each is used under its own licence, with attribution below.</p>

    <h2 :class="bemm('heading')">Figtree</h2>
    <p :class="bemm('copy')">The typeface used throughout both apps. Version 2.002, bundled unmodified.</p>
    <p :class="bemm('copy')">Copyright 2022 The Figtree Project Authors. Licensed under the <a :class="bemm('link')" href="https://openfontlicense.org">SIL Open Font License, Version 1.1</a>.</p>

    <h2 :class="bemm('heading')">Apple frameworks</h2>
    <p :class="bemm('copy')">SwiftUI, AppKit, Core Graphics, Core Image, Core ML, Image I/O, AVFoundation, AVKit, VideoToolbox and Uniform Type Identifiers. These ship with macOS and are not redistributed.</p>

    <h2 :class="bemm('heading')">Contact</h2>
    <p :class="bemm('copy')">Questions about attribution or licensing can be sent to <a :class="bemm('link')" href="mailto:hello@hakobs.com">hello@hakobs.com</a>.</p>

    <p :class="bemm('last-updated')">Last updated: 24 Jul 2026</p>
  </div>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";

const bemm = useBemm("acknowledgements-page", { includeBaseClass: true });
</script>
