<template>
  <DocsShell>
    <div :class="bemm()">
      <p :class="bemm('eyebrow')">Documentation</p>
      <h1 :class="bemm('title')">Build and understand ImageKid.</h1>
      <p :class="bemm('lead')">Guides for the checked-in native implementation, its current limits, and the path toward a distributable Mac app.</p>
      <aside :class="bemm('boundary')">
        <div :class="bemm('boundary-copy')">
          <strong>Development boundary</strong>
          <span>ImageKid currently runs as a Swift package built from source. There is no signed, sandboxed, notarised, or App Store release.</span>
        </div>
        <Button to="/docs/getting-started" variant="primary">Start with the build guide</Button>
      </aside>
      <div :class="bemm('index')">
        <RouterLink
          v-for="(item, index) in docsNavigation"
          :key="item.to"
          :class="bemm('index-link', index === 0 ? 'primary' : '')"
          :to="item.to"
        >
          <span :class="bemm('index-number')">0{{ index + 1 }}</span>
          <strong :class="bemm('index-title')">{{ item.label }}</strong>
          <span :class="bemm('index-description')">{{ item.description }}</span>
        </RouterLink>
      </div>
    </div>
  </DocsShell>
</template>

<script setup lang="ts">
import { Button } from "@sil/ui";
import { useBemm } from "bemm";
import { RouterLink } from "vue-router";
import DocsShell from "../components/DocsShell";
import { docsNavigation } from "../components/DocsShell/DocsShell.model";

const bemm = useBemm("docs-index-page", { includeBaseClass: true });
</script>
