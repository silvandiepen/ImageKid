<template>
  <ProductPage :data="data" />
</template>

<script setup lang="ts">
import ProductPage from "../components/ProductPage";
import type { ProductPageData } from "../components/ProductPage";
import { appById } from "../data/apps";

const meta = appById("cutout")!;
const data: ProductPageData = {
  id: meta.id,
  name: meta.name,
  icon: meta.icon,
  accent: meta.accent,
  eyebrow: "Batch background remover for Mac",
  tagline: "Transparent cut-outs, a folder at a time.",
  lead:
    "ImageKid Cutout removes backgrounds from a whole batch on your Mac and writes clean transparent PNGs. Perfect for product shots, portraits, icons, and generated assets — no service fees, no uploads.",
  chips: ["macOS", "On-device", "One-time purchase"],
  actions: [
    { label: "Get notified", to: "mailto:hello@hakobs.com?subject=ImageKid%20Cutout", variant: "primary", external: true },
    { label: "See ImageKid", to: "/imagekid", variant: "outline" }
  ],
  featuresEyebrow: "How it works",
  featuresTitle: "Drop, remove, generate.",
  features: [
    { title: "Drag in a batch", description: "Drop files or add them from the Open panel. Each row shows a thumbnail, status, and progress." },
    { title: "Built-in or Best Quality", description: "Apple Vision removal is always available; an optional on-device Core ML model handles hair and tricky edges." },
    { title: "Transparent PNGs", description: "Outputs PNGs with a real alpha channel so your cut-outs drop straight onto any background." },
    { title: "Safe output", description: "Writes to a sibling ImageKid Cutouts folder with collision-safe names. Originals are left untouched." },
    { title: "Serial & predictable", description: "One image at a time to stay light on memory and heat, with per-file errors, cancel, and retry." },
    { title: "Shared model cache", description: "Best-quality models live in the shared ImageKid App Group, downloaded once across the family." }
  ],
  sections: [
    {
      eyebrow: "Why it exists",
      title: "Repeated cut-outs shouldn't cost a subscription.",
      copy:
        "If your recurring job is removing backgrounds from a batch, a hosted tool charges every time. Cutout is a small, one-time-purchase utility built on the same local engine as ImageKid.",
      bullets: ["No subscription or credits", "No account, no telemetry", "Runs fully on-device"],
      imageSide: "right",
      tone: 1
    }
  ],
  closingTitle: "Part of the ImageKid family.",
  closingCopy: "Want the full editor or batch upscaling instead? They share the same local-first foundation."
};
</script>
