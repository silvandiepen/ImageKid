<template>
  <div :class="bemm()">
    <section v-for="section in sections" :key="section.title" :class="bemm('section')">
      <h3 :class="bemm('section-title')">{{ section.title }}</h3>
      <dl :class="bemm('list')">
        <div v-for="item in section.items" :key="item.label" :class="bemm('row')">
          <dt :class="bemm('label')">{{ item.label }}</dt>
          <dd :class="bemm('keys')"><kbd>{{ item.keys }}</kbd></dd>
        </div>
      </dl>
    </section>
  </div>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";
import type { ShortcutSection } from "../data/shortcuts";

defineProps<{ sections: ShortcutSection[] }>();

const bemm = useBemm("shortcut-table", { includeBaseClass: true });
</script>

<style lang="scss">
.shortcut-table {
  display: grid;
  gap: var(--space-xl);

  &__section-title {
    margin-bottom: var(--space-s);
    font-size: var(--font-size-default);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    opacity: 0.55;
  }

  &__list { display: grid; margin: 0; }

  &__row {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: var(--space-m);
    padding: var(--space-s) 0;
    border-bottom: var(--border-width) solid
      color-mix(in srgb, var(--color-foreground), transparent 90%);

    &:last-child { border-bottom: 0; }
  }

  &__label { margin: 0; }

  &__keys {
    margin: 0;
    flex-shrink: 0;
    font-variant-numeric: tabular-nums;
  }
}
</style>
