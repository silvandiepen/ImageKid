<template>
  <article :class="[bemm(), `product-page--${data.id}`]">
    <section :class="bemm('hero')">
      <div :class="bemm('hero-copy')">
        <div :class="bemm('eyebrow-row')">
          <p :class="bemm('eyebrow')">{{ data.eyebrow }}</p>
          <span v-if="status" :class="bemm('status')">{{ status }}</span>
        </div>
        <div :class="bemm('identity')">
          <img :class="bemm('hero-icon')" :src="data.icon" :alt="`${data.name} app icon`" width="72" height="72" />
          <h1 :class="bemm('title')">{{ data.tagline }}</h1>
        </div>
        <p :class="bemm('lead')">{{ data.lead }}</p>
        <div :class="bemm('actions')">
          <template v-for="action in data.actions" :key="action.label">
            <Button
              v-if="action.external"
              :href="action.to"
              :variant="action.variant ?? 'primary'"
            >{{ action.label }}</Button>
            <Button
              v-else
              :to="action.to"
              :variant="action.variant ?? 'primary'"
            >{{ action.label }}</Button>
          </template>
        </div>
        <p :class="bemm('chips')"><span v-for="chip in data.chips" :key="chip">{{ chip }}</span></p>
      </div>

      <figure v-if="data.heroImage" :class="bemm('hero-media')">
        <img :class="bemm('hero-image')" :src="data.heroImage" :alt="data.heroImageAlt ?? data.name" />
      </figure>
      <div v-else :class="bemm('hero-panel')" aria-hidden="true">
        <img :class="bemm('hero-panel-icon')" :src="data.icon" :alt="`${data.name} app icon`" width="132" height="132" />
      </div>
    </section>

    <section v-if="data.features?.length" :class="bemm('features')">
      <div :class="bemm('section-intro')">
        <p :class="bemm('eyebrow')">{{ data.featuresEyebrow ?? 'Features' }}</p>
        <h2 :class="bemm('heading')">{{ data.featuresTitle ?? 'What it does.' }}</h2>
      </div>
      <div :class="bemm('feature-grid')">
        <article v-for="feature in data.features" :key="feature.title" :class="bemm('feature')">
          <span :class="bemm('feature-marker')" aria-hidden="true" />
          <h3 :class="bemm('feature-title')">{{ feature.title }}</h3>
          <p :class="bemm('feature-copy')">{{ feature.description }}</p>
        </article>
      </div>
    </section>

    <section
      v-for="(section, index) in data.sections ?? []"
      :key="section.title"
      :class="[
        bemm('band', `tone-${section.tone ?? ((index % 3) + 1)}`),
        section.imageSide === 'left' ? bemm('band', 'image-left') : ''
      ]"
    >
      <div :class="bemm('band-inner')">
        <div :class="bemm('band-copy')">
          <p :class="bemm('eyebrow')">{{ section.eyebrow }}</p>
          <h2 :class="bemm('band-title')">{{ section.title }}</h2>
          <p v-if="section.copy" :class="bemm('band-lead')">{{ section.copy }}</p>
          <ul v-if="section.bullets?.length" :class="bemm('band-list')">
            <li v-for="bullet in section.bullets" :key="bullet">{{ bullet }}</li>
          </ul>
        </div>
        <figure v-if="section.image" :class="bemm('band-media')">
          <img :class="bemm('band-image')" :src="section.image" :alt="section.imageAlt ?? section.title" />
        </figure>
        <div v-else :class="bemm('band-panel')" aria-hidden="true">
          <img :src="data.icon" :alt="''" width="96" height="96" />
        </div>
      </div>
    </section>

    <section :class="bemm('family')">
      <div :class="bemm('section-intro')">
        <p :class="bemm('eyebrow')">The family</p>
        <h2 :class="bemm('heading')">{{ data.closingTitle ?? 'Part of the ImageKid family.' }}</h2>
        <p v-if="data.closingCopy" :class="bemm('section-copy')">{{ data.closingCopy }}</p>
      </div>
      <div :class="bemm('family-grid')">
        <RouterLink
          v-for="app in siblings"
          :key="app.id"
          :class="bemm('family-card', app.id)"
          :to="app.to"
        >
          <img :class="bemm('family-icon')" :src="app.icon" :alt="`${app.name} app icon`" width="48" height="48" />
          <span :class="bemm('family-name')">{{ app.name }}</span>
          <span :class="bemm('family-tagline')">{{ app.tagline }}</span>
        </RouterLink>
      </div>
    </section>
  </article>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { Button } from "@sil/ui";
import { useBemm } from "bemm";
import { RouterLink } from "vue-router";
import { otherApps, appById } from "../../data/apps";
import type { ProductPageData } from "./ProductPage.model";

const props = defineProps<{ data: ProductPageData }>();
const bemm = useBemm("product-page", { includeBaseClass: true });
const siblings = computed(() => otherApps(props.data.id));
const status = computed(() => appById(props.data.id)?.status ?? "");
</script>
