<template>
  <div :class="bemm()">
    <p :class="bemm('eyebrow')">404</p>
    <h1 :class="bemm('title')">This page is not here.</h1>
    <p :class="bemm('copy')">The address may have changed. Return to the product overview or open the documentation.</p>
    <div :class="bemm('actions')">
      <Button to="/" variant="primary">Go home</Button>
      <Button to="/docs" variant="outline">Read docs</Button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { Button } from "@sil/ui";
import { useBemm } from "bemm";

const bemm = useBemm("not-found-page", { includeBaseClass: true });
</script>
