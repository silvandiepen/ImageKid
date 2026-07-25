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
  eyebrow: "Batch background remover for Mac",
  tagline: "Backgrounds, gone.",
  lead:
    "Point it at a folder of product shots, portraits or generated assets. It hands back transparent PNGs, cut on your Mac, with nothing uploaded and nothing billed per image.",
  chips: ["macOS", "On-device", "No subscription"],
  actions: [
    { label: "Get notified", to: "mailto:hello@hakobs.com?subject=ImageKid%20Cutout", variant: "primary", external: true },
    { label: "See ImageKid", to: "/imagekid", variant: "outline" }
  ],
  featuresEyebrow: "How it works",
  featuresTitle: "Three steps. That is the whole app.",
  features: [
    { title: "Drag in a batch", icon: "ui/box-in", description: "Drop the files in. Each row shows a thumbnail, a status and a progress bar." },
    { title: "Two levels of good", icon: "ui/chart-bars-squared", description: "Apple Vision is always there and instant. Best Quality downloads a model that copes with hair and other nightmares — still on your Mac." },
    { title: "Real transparency", icon: "ui/rounded-square-grid", description: "PNGs with a proper alpha channel, so the cut-outs drop onto any background without a white halo." },
    { title: "Your originals survive", icon: "ui/folder-check", description: "Results go to a sibling folder with collision-safe names. The files you dropped in are left alone." },
    { title: "One at a time, on purpose", icon: "ui/list-numbered", description: "Serial processing keeps memory and heat sane on a laptop. Cancel whenever; finished files stay finished." },
    { title: "Downloads models once", icon: "arrows/arrow-download", description: "The big models live in a shared cache, so nothing in the family fetches the same one twice." }
  ],
  sections: [
    {
      eyebrow: "Why it exists",
      title: "You should not rent this.",
      copy:
        "If cutting backgrounds out of a batch is a thing you do every week, a hosted tool charges you every week. This is a small one-time-purchase utility on the same local engine as ImageKid.",
      bullets: ["No subscription, no credits", "No account, no telemetry", "Never leaves your Mac"],
      image: "/media/accent/cutout-checker.jpg",
      imageAlt: "",
      imageSide: "right",
      tone: 2
    }
  ],
  closingTitle: "One of four.",
  closingCopy: "Want the full editor, or the one that makes things bigger instead? Same engine underneath."
};
</script>
