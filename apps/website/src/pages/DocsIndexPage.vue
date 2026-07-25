<template>
  <DocsShell>
    <div :class="bemm()">
      <p :class="bemm('eyebrow')">Documentation</p>
      <h1 :class="bemm('title')">Understand ImageKid.</h1>
      <p :class="bemm('lead')">Guides for the local image workflow, privacy model, Magic provider boundary, and current product scope.</p>
      <aside :class="bemm('boundary')">
        <div :class="bemm('boundary-copy')">
          <strong>Local-first boundary</strong>
          <span>Background removal, upscaling, crop, resize, annotation, export, and batches are local-first. Magic is the provider-backed exception.</span>
        </div>
        <Button to="/features" variant="primary">Explore features</Button>
      </aside>
      <div :class="bemm('index')">
        <RouterLink
          v-for="(item, index) in docsNavigation"
          :key="item.to"
          :class="bemm('index-link', index === 0 ? 'primary' : '')"
          :to="item.to"
        >
          <span :class="bemm('index-number')">
            <Icon :name="item.icon" size="small" aria-hidden="true" />
            0{{ index + 1 }}
          </span>
          <strong :class="bemm('index-title')">{{ item.label }}</strong>
          <span :class="bemm('index-description')">{{ item.description }}</span>
        </RouterLink>
      </div>
    </div>
  </DocsShell>
</template>

<script setup lang="ts">
import { Button, Icon } from "@sil/ui";
import { useBemm } from "bemm";
import { RouterLink } from "vue-router";
import DocsShell from "../components/DocsShell";
import { docsNavigation } from "../components/DocsShell/DocsShell.model";

const bemm = useBemm("docs-index-page", { includeBaseClass: true });
</script>
