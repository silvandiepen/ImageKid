<template>
  <figure :class="bemm('', variant)" aria-hidden="true">
    <img
      v-if="screenshot"
      :class="bemm('shot')"
      :src="screenshot"
      alt=""
      loading="eager"
      decoding="async"
    />
    <img
      :class="bemm('character')"
      :src="character"
      alt=""
      loading="eager"
      decoding="async"
    />
  </figure>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";

withDefaults(
  defineProps<{
    /** Cut-out character render, transparent PNG. */
    character: string;
    /** Real app screenshot sitting behind the character. */
    screenshot?: string;
    /** Colour key, e.g. "imagekid" | "fekthor". */
    variant?: string;
  }>(),
  { variant: "imagekid" }
);

const bemm = useBemm("app-hero", { includeBaseClass: true });
</script>

<style lang="scss">
// The character stands on the family's warm cream, with a real screenshot
// tucked behind it. No frame around the character — it is a cut-out and reads
// as standing in the panel, not pasted onto it.
.app-hero {
  position: relative;
  margin: 0;
  display: grid;
  place-items: end center;
  aspect-ratio: 4 / 3;
  padding: var(--space-xl) var(--space-xl) 0;
  border-radius: var(--border-radius-xl, 24px);
  overflow: hidden;
  background:
    radial-gradient(120% 90% at 78% 8%, rgb(255 255 255 / 0.55), transparent 60%),
    linear-gradient(170deg, var(--color-cream) 0%, color-mix(in srgb, var(--color-cream), #e8b978 55%) 100%);

  &__shot {
    position: absolute;
    right: -6%;
    bottom: 14%;
    width: 74%;
    height: auto;
    border-radius: var(--border-radius-l);
    box-shadow:
      0 2px 6px rgb(20 16 8 / 0.10),
      0 24px 60px rgb(20 16 8 / 0.28);
    transform: rotate(2.5deg);
  }

  &__character {
    position: relative;
    z-index: 1;
    width: 46%;
    max-width: 340px;
    height: auto;
    justify-self: start;
    // Pushed past the bottom edge so the feet crop, matching the apps'
    // own home screens.
    margin-bottom: -6%;
    filter: drop-shadow(0 24px 34px rgb(20 16 8 / 0.30));
  }

  &--fekthor {
    background:
      radial-gradient(120% 90% at 78% 8%, rgb(255 255 255 / 0.5), transparent 60%),
      linear-gradient(170deg, var(--color-cream) 0%, color-mix(in srgb, var(--color-cream), #d98a3c 55%) 100%);
  }

  @media (max-width: 720px) {
    aspect-ratio: 5 / 4;
    padding: var(--space-l) var(--space-l) 0;

    &__shot { right: -12%; width: 86%; }
    &__character { width: 54%; }
  }
}
</style>
