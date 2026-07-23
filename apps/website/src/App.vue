<template>
  <PillHeader
    :nav-items="navItems"
    :actions="actions"
    :current-path="route.path"
    :color-mode="theme"
    brand-to="/"
    brand-suffix="ImageKid"
    brand-aria-label="ImageKid home"
  >
    <template #brand-mark>
      <span aria-hidden="true"><ImageKidMark :size="24" /></span>
    </template>
  </PillHeader>
  <main :class="bemm('main')">
    <RouterView />
  </main>
  <SiteFooter />
</template>

<script setup lang="ts">
import { computed } from "vue";
import { useBemm } from "bemm";
import { PillHeader } from "@sil/ui";
import type { PillHeaderAction, PillHeaderNavItem } from "@sil/ui";
import { RouterView, useRoute } from "vue-router";

import ImageKidMark from "./components/ImageKidMark";
import SiteFooter from "./components/SiteFooter";
import { useColorMode } from "./composables/useColorMode";

const bemm = useBemm("app-shell", { includeBaseClass: true });
const route = useRoute();
const { mode, theme, cycleMode } = useColorMode();
const navItems: PillHeaderNavItem[] = [
  { label: "Apps", to: "/#apps" },
  { label: "ImageKid", to: "/imagekid" },
  { label: "Fekthor", to: "/fekthor" },
  { label: "Docs", to: "/docs" },
  { label: "Support", to: "/support" }
];
const actions = computed<PillHeaderAction[]>(() => [{
  label: `Color mode: ${mode.value}. Change mode`,
  icon: theme.value === "dark" ? "weather/sun" : "weather/moon-dark-mode",
  iconOnly: true,
  handler: cycleMode
}]);
</script>
