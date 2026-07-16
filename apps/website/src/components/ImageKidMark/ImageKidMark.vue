<template>
  <svg :class="bemm()" :width="size" :height="size" viewBox="0 0 64 64" fill="none" role="img" :aria-label="title">
    <rect x="13" y="18" width="35" height="31" rx="6" stroke="currentColor" stroke-width="4" />
    <path d="M19 41l9-10 7 7 6-6 7 8" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" />
    <path d="M21 12h27a6 6 0 0 1 6 6v24" stroke="currentColor" stroke-width="4" stroke-linecap="round" />
    <circle cx="38" cy="28" r="3" fill="currentColor" />
  </svg>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";

import type { ImageKidMarkProps } from "./ImageKidMark.model";

withDefaults(defineProps<ImageKidMarkProps>(), { size: 32, title: "ImageKid" });
const bemm = useBemm("imagekid-mark", { includeBaseClass: true });
</script>
