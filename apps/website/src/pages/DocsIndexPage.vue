<template>
  <DocsShell>
    <div :class="bemm()">
      <p :class="bemm('eyebrow')">Documentation</p>
      <h1 :class="bemm('title')">Build and understand ImageKid.</h1>
      <p :class="bemm('lead')">The native app is an early-stage Swift package. These guides reflect the checked-in implementation, its limits, and the path toward a distributable Mac app.</p>
      <div :class="bemm('index')">
        <RouterLink v-for="item in items" :key="item.to" :class="bemm('index-link')" :to="item.to">
          <strong :class="bemm('index-title')">{{ item.label }}</strong>
          <span :class="bemm('index-description')">{{ item.description }}</span>
        </RouterLink>
      </div>
    </div>
  </DocsShell>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";
import { RouterLink } from "vue-router";
import DocsShell from "../components/DocsShell";
import type { DocsNavItem } from "../components/DocsShell";

const bemm = useBemm("docs-index-page", { includeBaseClass: true });
const items: DocsNavItem[] = [
  { label: "Getting started", to: "/docs/getting-started", description: "Requirements, build commands, and release boundary." },
  { label: "Workflows", to: "/docs/workflows", description: "Opening, keyboard controls, image editing, and image export." },
  { label: "Architecture", to: "/docs/architecture", description: "Native app structure, edit state, rendering, and monorepo boundaries." },
  { label: "Roadmap", to: "/docs/roadmap", description: "Implemented, incomplete, and deferred work." }
];
</script>
