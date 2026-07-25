<template>
  <figure :class="bemm()">
    <div
      :class="bemm('grid')"
      :style="{ '--matrix-columns': partials.length }"
    >
      <span :class="bemm('corner')">
        <span :class="bemm('corner-label')">slot</span>
      </span>

      <span
        v-for="(partial, column) in partials"
        :key="partial.name"
        :class="bemm('head', ['partial', column === activeColumn ? 'active' : ''])"
      >
        <Icon :name="partial.icon" size="medium" aria-hidden="true" />
        <span :class="bemm('label')">{{ partial.name }}</span>
      </span>

      <template v-for="(container, row) in containers" :key="container.name">
        <span :class="bemm('head', ['container', row === activeRow ? 'active' : ''])">
          <Icon :name="container.icon" size="large" aria-hidden="true" />
          <span :class="bemm('label')">{{ container.name }}</span>
        </span>
        <span
          v-for="(partial, column) in partials"
          :key="`${container.name}-${partial.name}`"
          :class="bemm('cell', row === activeRow && column === activeColumn ? 'active' : '')"
        >
          <Icon :name="composedIconName(container, partial)" size="large" aria-hidden="true" />
        </span>
      </template>
    </div>

    <figcaption :class="bemm('legend')">
      <span :class="bemm('legend-item', 'container')">Container</span>
      <span :class="bemm('legend-item', 'partial')">Partial</span>
      <span :class="bemm('legend-item', 'composed')">{{ composedLabel }}</span>
    </figcaption>
  </figure>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import { Icon } from "@sil/ui";
import { useBemm } from "bemm";

import type { IconMatrixProps } from "./IconMatrix.model";
import { composedIconName, iconMatrixContainers, iconMatrixPartials } from "./IconMatrix.model";

const props = withDefaults(defineProps<IconMatrixProps>(), {
  containers: () => iconMatrixContainers,
  partials: () => iconMatrixPartials,
  interval: 1400
});

const bemm = useBemm("icon-matrix", { includeBaseClass: true });

const cellCount = computed(() => props.containers.length * props.partials.length);
const step = ref(0);
const activeRow = computed(() => Math.floor(step.value / props.partials.length));
const activeColumn = computed(() => step.value % props.partials.length);
const composedLabel = computed(() => `${cellCount.value} composed, one export`);

// The highlight walks the matrix so the container, the partial and the glyph
// they compose into read as one relationship. Static for reduced motion.
let timer: ReturnType<typeof setInterval> | undefined;

onMounted(() => {
  if (typeof window === "undefined") return;
  if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return;

  timer = setInterval(() => {
    step.value = (step.value + 1) % cellCount.value;
  }, props.interval);
});

onBeforeUnmount(() => {
  if (timer) clearInterval(timer);
});
</script>
