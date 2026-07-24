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
  tagline: "Small pictures, made big.",
  lead:
    "Drop in a folder. Pick 2×, 4× or 8×. Walk away. Every image comes back bigger, done on your Mac, with no credits ticking down while you wait.",
  chips: ["macOS", "On-device", "No subscription"],
  actions: [
    { label: "Get notified", to: "mailto:hello@hakobs.com?subject=ImageKid%20Upscale", variant: "primary", external: true },
    { label: "See ImageKid", to: "/imagekid", variant: "outline" }
  ],
  featuresEyebrow: "How it works",
  featuresTitle: "Three steps. That is the whole app.",
  features: [
    { title: "Drag in a batch", icon: "ui/box-in", description: "Drop the files in. The queue shows a thumbnail, a status and a progress bar for each one." },
    { title: "Pick a scale", icon: "arrows/arrow-headed-out-center", description: "2×, 4× or 8×. Set it once; it applies to everything in the queue." },
    { title: "Two levels of good", icon: "ui/chart-bars-squared", description: "Standard is instant and always there. Best Quality downloads a model that squeezes out more detail — still on your Mac." },
    { title: "Your originals survive", icon: "ui/folder-check", description: "Results go to a sibling folder with collision-safe names. Nothing is overwritten unless you ask for it." },
    { title: "One at a time, on purpose", icon: "ui/list-numbered", description: "Serial processing keeps memory and heat sane on a laptop. Cancel whenever; finished files stay finished." },
    { title: "Downloads models once", icon: "arrows/arrow-download", description: "The big models live in a shared cache, so ImageKid and Upscale never fetch the same one twice." }
  ],
  sections: [
    {
      eyebrow: "Why it exists",
      title: "Your Mac can already do this.",
      copy:
        "Hosted upscalers bill you per image, or monthly, for a job the machine on your desk handles fine. This is a small one-time-purchase utility for people who run that job over and over.",
      bullets: ["No subscription, no credits", "No account, no telemetry", "Never leaves your Mac"],
      image: "/media/accent/upscale-closeup.jpg",
      imageAlt: "",
      imageSide: "right",
      tone: 2
    }
  ],
  closingTitle: "One of four.",
  closingCopy: "Want the full editor, or the one that removes backgrounds instead? Same engine underneath."
};
</script>
