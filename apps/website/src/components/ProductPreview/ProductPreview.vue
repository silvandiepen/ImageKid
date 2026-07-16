<template>
  <figure :class="bemm('', compact ? 'compact' : '')" aria-label="Illustrated representation of the ImageKid interface">
    <div :class="bemm('window')">
      <div :class="bemm('titlebar')">
        <span :class="bemm('traffic')" />
        <span :class="bemm('filename')">coast.heic</span>
        <span :class="bemm('zoom')">72%</span>
      </div>
      <div :class="bemm('canvas')">
        <div :class="bemm('image')">
          <div :class="bemm('sun')" />
          <div :class="bemm('ridge')" />
          <span v-for="corner in corners" :key="corner" :class="bemm('handle', corner)" />
        </div>
        <div :class="bemm('readout')">
          <span :class="bemm('swatch')" />
          <span :class="bemm('colour-value')">#315FDB</span>
          <span :class="bemm('coordinates')">49, 86</span>
        </div>
        <div :class="bemm('toolbar')">
          <span :class="bemm('tool')">View</span>
          <strong :class="bemm('tool', 'active')">Pick</strong>
          <span :class="bemm('tool')">Crop</span>
          <span :class="bemm('tool', 'optional')">Draw</span>
          <span :class="bemm('tool', 'optional')">Text</span>
          <span :class="bemm('tool', 'optional')">Export</span>
        </div>
      </div>
    </div>
    <figcaption :class="bemm('caption')">Interface representation based on the current native build.</figcaption>
  </figure>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";

import type { ProductPreviewProps } from "./ProductPreview.model";

withDefaults(defineProps<ProductPreviewProps>(), { compact: false });
const bemm = useBemm("product-preview", { includeBaseClass: true });
const corners = ["top-left", "top-right", "bottom-left", "bottom-right"];
</script>
