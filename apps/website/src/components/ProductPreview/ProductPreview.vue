<template>
  <figure :class="bemm('', compact ? 'compact' : '')" aria-label="Illustrated representation of the ImageKid interface">
    <div :class="bemm('window')">
      <div :class="bemm('titlebar')">
        <span :class="bemm('traffic')" aria-hidden="true"><i /><i /><i /></span>
        <span :class="bemm('app-name')">ImageKid</span>
        <span :class="bemm('document')">coast.heic</span>
      </div>
      <div :class="bemm('canvas')">
        <div :class="bemm('image')" aria-hidden="true">
          <div :class="bemm('sun')" />
          <div :class="bemm('ridge', 'far')" />
          <div :class="bemm('ridge', 'near')" />
        </div>

        <aside :class="bemm('palette')">
          <div :class="bemm('palette-heading')">
            <strong>Picked Colours</strong>
            <span>2 saved</span>
          </div>
          <div :class="bemm('colour-row')">
            <span :class="bemm('swatch', 'primary')" />
            <span><strong>#315FDB</strong><small>49, 95, 219</small></span>
          </div>
          <div :class="bemm('colour-row')">
            <span :class="bemm('swatch', 'ink')" />
            <span><strong>#151820</strong><small>21, 24, 32</small></span>
          </div>
        </aside>

        <div :class="bemm('picker')">
          <span :class="bemm('picker-swatch')" />
          <span><strong>#315FDB</strong><small>RGB 49 95 219</small></span>
        </div>

        <div :class="bemm('toolbar')" aria-label="ImageKid tools">
          <span
            v-for="tool in tools"
            :key="tool.label"
            :class="bemm('tool', tool.active ? 'active' : '')"
          >
            <Icon :name="tool.icon" size="small" aria-hidden="true" />
            <span>{{ tool.label }}</span>
          </span>
        </div>
      </div>
    </div>
    <figcaption :class="bemm('caption')">
      <strong :class="bemm('caption-label')">Local Mac workflow</strong>
      <span>Interface representation of ImageKid with the Pick Colour tool active.</span>
    </figcaption>
  </figure>
</template>

<script setup lang="ts">
import { Icon } from "@sil/ui";
import { useBemm } from "bemm";

import type { ProductPreviewProps } from "./ProductPreview.model";
import { productPreviewTools } from "./ProductPreview.model";

withDefaults(defineProps<ProductPreviewProps>(), { compact: false });
const bemm = useBemm("product-preview", { includeBaseClass: true });
const tools = productPreviewTools;
</script>
