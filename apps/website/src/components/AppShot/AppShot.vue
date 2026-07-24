<template>
  <picture :class="bemm()">
    <img :class="bemm('img', 'light')" :src="src" :alt="alt" loading="lazy" decoding="async" />
    <img
      v-if="darkSrc"
      :class="bemm('img', 'dark')"
      :src="darkSrc"
      :alt="alt"
      loading="lazy"
      decoding="async"
    />
  </picture>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { useBemm } from "bemm";

const props = defineProps<{
  /** Light-mode capture. */
  src: string;
  alt?: string;
}>();

const bemm = useBemm("app-shot", { includeBaseClass: true });

/// Dark captures live beside the light ones as `<name>-dark.jpg`, so a caller
/// only ever names one file.
const darkSrc = computed(() => props.src.replace(/\.(jpg|jpeg|png)$/, "-dark.$1"));
</script>

<style lang="scss">
// The site resolves its theme to a data-theme attribute on <html> (the toggle
// can override the OS), so the swap keys off that rather than a media query.
.app-shot {
  display: block;

  &__img {
    width: 100%;
    height: auto;
    display: block;
    border-radius: var(--border-radius-l);
  }

  &__img--dark { display: none; }
}

html[data-theme="dark"] .app-shot {
  &__img--light { display: none; }
  &__img--dark { display: block; }
}
</style>
