<template>
  <figure :class="bemm()">
    <div :class="bemm('panel')">
      <div :class="bemm('header')">
        <span :class="bemm('folder')">
          <Icon name="ui/folder" size="small" aria-hidden="true" />
          <span>{{ folder }}</span>
        </span>
        <span :class="bemm('count')">{{ visible.length }} of {{ total }}</span>
      </div>

      <div :class="bemm('categories')">
        <button
          v-for="category in categoryFilters"
          :key="category"
          type="button"
          :aria-pressed="active === category"
          :class="bemm('category', active === category ? 'active' : '')"
          @click="active = category"
        >{{ category }}</button>
      </div>

      <ul :class="bemm('grid')">
        <li
          v-for="(entry, index) in visible"
          :key="entry.icon"
          :class="bemm('cell')"
          :style="{ '--cell-index': index }"
        >
          <Icon :name="entry.icon" size="large" aria-hidden="true" />
          <span :class="bemm('name')">{{ entry.name }}.svg</span>
        </li>
      </ul>
    </div>
    <figcaption :class="bemm('caption')">
      Subfolders become categories. Every glyph here is a real SVG from an icon set.
    </figcaption>
  </figure>
</template>

<script setup lang="ts">
import { computed, ref } from "vue";
import { Icon } from "@sil/ui";
import { useBemm } from "bemm";

import type { IconGalleryProps } from "./IconGallery.model";
import { iconGalleryCategories } from "./IconGallery.model";

const props = withDefaults(defineProps<IconGalleryProps>(), {
  folder: "icons/",
  categories: () => iconGalleryCategories
});

const bemm = useBemm("icon-gallery", { includeBaseClass: true });

const ALL = "all";
const active = ref(ALL);
const categoryFilters = computed(() => [ALL, ...props.categories.map((category) => category.id)]);
const total = computed(() => props.categories.reduce((sum, category) => sum + category.entries.length, 0));
const visible = computed(() =>
  props.categories
    .filter((category) => active.value === ALL || category.id === active.value)
    .flatMap((category) => category.entries)
);
</script>
