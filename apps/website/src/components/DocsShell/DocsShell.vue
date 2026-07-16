<template>
  <div :class="bemm()">
    <aside :class="bemm('sidebar')">
      <RouterLink :class="bemm('index-link')" to="/docs">Documentation</RouterLink>
      <nav :class="bemm('nav')" aria-label="Documentation">
        <RouterLink
          v-for="item in docsNavigation"
          :key="item.to"
          :class="bemm('link', route.path === item.to ? 'active' : '')"
          :to="item.to"
        >
          {{ item.label }}
        </RouterLink>
      </nav>
    </aside>
    <article :class="bemm('content')">
      <slot />
    </article>
  </div>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";
import { useRoute, RouterLink } from "vue-router";
import type { DocsNavItem } from "./DocsShell.model";

const bemm = useBemm("docs-shell", { includeBaseClass: true });
const route = useRoute();
const docsNavigation: DocsNavItem[] = [
  { label: "Getting started", to: "/docs/getting-started", description: "Requirements and commands" },
  { label: "Workflows", to: "/docs/workflows", description: "Open, inspect, edit, export" },
  { label: "Architecture", to: "/docs/architecture", description: "Native and web boundaries" },
  { label: "Roadmap", to: "/docs/roadmap", description: "Current and planned work" }
];
</script>
