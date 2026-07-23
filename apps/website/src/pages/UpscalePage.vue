<template>
  <ProductPage :data="data" />
</template>

<script setup lang="ts">
import ProductPage from "../components/ProductPage";
import type { ProductPageData } from "../components/ProductPage";
import { appById } from "../data/apps";

const meta = appById("upscale")!;
const data: ProductPageData = {
  id: meta.id,
  name: meta.name,
  icon: meta.icon,
  eyebrow: "Batch upscaler for Mac",
  tagline: "Enlarge a whole folder, locally.",
  lead:
    "ImageKid Upscale does one thing well: drop in a batch of images, pick a scale, and it enlarges every one on your Mac. No accounts, no credits, no per-image fees — pay once and keep using it.",
  chips: ["macOS", "On-device", "No subscription"],
  actions: [
    { label: "Get notified", to: "mailto:hello@hakobs.com?subject=ImageKid%20Upscale", variant: "primary", external: true },
    { label: "See ImageKid", to: "/imagekid", variant: "outline" }
  ],
  featuresEyebrow: "How it works",
  featuresTitle: "Drop, scale, generate.",
  features: [
    { title: "Drag in a batch", description: "Drop files or add them from the Open panel. The queue shows a thumbnail, status, and progress per file." },
    { title: "Pick a scale", description: "2×, 4×, or 8× — set it once and it applies to the whole queue." },
    { title: "Standard or Best Quality", description: "A fast, always-available Core Image path, or an optional on-device Core ML upscaler for maximum detail." },
    { title: "Safe output", description: "Writes to a sibling ImageKid Upscaled folder with collision-safe names. Originals are never overwritten unless you choose to." },
    { title: "Serial & predictable", description: "Processes one image at a time to keep memory and heat under control, with per-file status and cancel." },
    { title: "Shared model cache", description: "Best-quality models live in the shared ImageKid App Group, so ImageKid and Upscale never download them twice." }
  ],
  sections: [
    {
      eyebrow: "Why it exists",
      title: "Pay once, not per image.",
      copy:
        "Hosted upscalers charge subscriptions or credits for work your Mac can already do. Upscale is a focused, one-time-purchase utility for the people who run this job again and again.",
      bullets: ["No subscription or credits", "No account, no telemetry", "Runs fully on-device"],
      imageSide: "right",
      tone: 1
    }
  ],
  closingTitle: "Part of the ImageKid family.",
  closingCopy: "Need the full editor or a batch background remover instead? They share the same engine."
};
</script>
