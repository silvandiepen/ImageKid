<template>
  <div :class="bemm()">
    <aside :class="bemm('sidebar')">
      <RouterLink :class="bemm('index-link')" to="/docs">
        <Icon name="ui/book" size="small" aria-hidden="true" />
        Documentation
      </RouterLink>
      <nav :class="bemm('nav')" aria-label="Documentation">
        <RouterLink
          v-for="item in docsNavigation"
          :key="item.to"
          :class="bemm('link', route.path === item.to ? 'active' : '')"
          :aria-current="route.path === item.to ? 'page' : undefined"
          :to="item.to"
        >
          <Icon :name="item.icon" size="small" aria-hidden="true" />
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
import { Icon } from "@sil/ui";
import { useBemm } from "bemm";
import { useRoute, RouterLink } from "vue-router";
import { docsNavigation } from "./DocsShell.model";

const bemm = useBemm("docs-shell", { includeBaseClass: true });
const route = useRoute();

</script>
