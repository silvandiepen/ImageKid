<template>
  <footer :class="bemm()">
    <div :class="bemm('inner')">
      <RouterLink :class="bemm('brand')" to="/">
        <span aria-hidden="true"><ImageKidMark :size="24" /></span>
        <span :class="bemm('brand-name')">ImageKid</span>
      </RouterLink>
      <nav :class="bemm('links')" aria-label="Apps">
        <RouterLink v-for="app in apps" :key="app.id" :class="bemm('link')" :to="app.to">
          <Icon :name="app.glyph" size="small" aria-hidden="true" />
          {{ app.name }}
        </RouterLink>
      </nav>
      <nav :class="bemm('links')" aria-label="Footer">
        <template v-for="link in links" :key="link.to">
          <a v-if="link.external" :class="bemm('link')" :href="link.to">
            <Icon v-if="link.icon" :name="link.icon" size="small" aria-hidden="true" />
            {{ link.label }}
          </a>
          <RouterLink v-else :class="bemm('link')" :to="link.to">
            <Icon v-if="link.icon" :name="link.icon" size="small" aria-hidden="true" />
            {{ link.label }}
          </RouterLink>
        </template>
      </nav>
      <p :class="bemm('note')">Native, local-first apps for Mac. Processing runs on your device; Magic uses your own AI provider.</p>
    </div>
  </footer>
</template>

<script setup lang="ts">
import { Icon } from "@sil/ui";
import { useBemm } from "bemm";
import { RouterLink } from "vue-router";
import ImageKidMark from "../ImageKidMark";
import { apps } from "../../data/apps";
import type { FooterLink } from "./SiteFooter.model";

const bemm = useBemm("site-footer", { includeBaseClass: true });
const links: FooterLink[] = [
  { label: "Docs", to: "/docs", icon: "ui/book" },
  { label: "Support", to: "/support", icon: "ui/talk" },
  { label: "Privacy", to: "/privacy", icon: "misc/shield" },
  { label: "Terms", to: "/terms", icon: "ui/file-text" }
];
</script>
