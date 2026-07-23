<template>
  <ProductPage :data="data" />
</template>

<script setup lang="ts">
import ProductPage from "../components/ProductPage";
import type { ProductPageData } from "../components/ProductPage";
import { appById } from "../data/apps";

const meta = appById("imagekid")!;
const data: ProductPageData = {
  id: meta.id,
  name: meta.name,
  icon: meta.icon,
  accent: meta.accent,
  eyebrow: "Native image editor for Mac, iPad & iPhone",
  tagline: "Everyday image editing, done on your device.",
  lead:
    "Open a picture and get straight to work: cut out the background, sharpen and enlarge it, crop, annotate, and export — without an account, a subscription, or an upload step. The heavy AI runs on-device, so your files stay yours.",
  chips: ["macOS 14 · iPadOS · iOS 17", "Universal purchase", "Local-first processing"],
  actions: [
    { label: "Explore the features", to: "/features", variant: "primary" },
    { label: "Read the privacy note", to: "/privacy", variant: "outline" }
  ],
  heroImage: "/media/app/workspace.jpg",
  heroImageAlt: "The ImageKid editor with an image open and the tool palette visible",
  featuresEyebrow: "In the box",
  featuresTitle: "A full editor, not a single trick.",
  features: [
    { title: "Remove backgrounds", description: "One tap to cut out subjects. A built-in remover for quick shots, plus an optional higher-quality on-device model for hair and tricky edges." },
    { title: "Enhance & upscale", description: "Sharpen and enlarge with quality grades — Quick, High, and Max — at the same size or 2× / 4×. AI models run locally." },
    { title: "Crop & resize", description: "Exact dimensions, aspect-lock, ratios, and drag handles for precise output sizes." },
    { title: "Rotate & flip", description: "Straighten, rotate, and mirror with a live canvas and clean re-rendering." },
    { title: "Draw, text & colour", description: "Annotate with shapes, arrows, freehand, and text, and sample exact pixel colours into a palette." },
    { title: "Private by default", description: "Core editing and downloaded models run on-device. No accounts, no analytics, no tracking." }
  ],
  sections: [
    {
      eyebrow: "Cut it out",
      title: "Background removal that respects the edges.",
      copy:
        "Tap once for an instant cut-out, or download the best-quality on-device model for fuzzy hair and busy scenes. Refine the mask by hand when you want the last word — nothing leaves your device.",
      bullets: ["Built-in remover, no download", "Optional best-quality on-device model", "Manual refine brush"],
      image: "/media/app/background-refine.jpg",
      imageAlt: "Refining a background cut-out in ImageKid",
      imageSide: "right",
      tone: 1
    },
    {
      eyebrow: "Bigger & sharper",
      title: "Enhance with quality grades, not model names.",
      copy:
        "Pick Quick for an instant built-in sharpen, or High and Max for on-device AI detail. Keep the same size or enlarge 2× / 4×. You choose the quality; ImageKid handles the model.",
      bullets: ["Quick · High · Max grades", "Same size, 2×, or 4×", "Runs entirely on-device"],
      image: "/media/app/resize.jpg",
      imageAlt: "Resize and enhance controls in ImageKid",
      imageSide: "left",
      tone: 2
    },
    {
      eyebrow: "Everyday tools",
      title: "Crop, annotate, inspect, export.",
      copy:
        "Crop to exact sizes, add shapes and text, sample colours, and export deliberate outputs rendered from your original plus your edits — never a lossy round-trip.",
      image: "/media/app/annotate.jpg",
      imageAlt: "Annotating an image in ImageKid",
      imageSide: "right",
      tone: 3
    },
    {
      eyebrow: "Magic",
      title: "AI edits — with your own key.",
      copy:
        "Magic is deliberately separate from the local tools. Describe an edit and ImageKid sends the image and prompt to your configured AI provider using your own key. No key, no sending — everything else stays local.",
      image: "/media/app/magic-provider-warning.jpg",
      imageAlt: "The Magic provider key notice in ImageKid",
      imageSide: "left",
      tone: 4
    }
  ],
  closingTitle: "Do it in bulk, or draw it from scratch.",
  closingCopy:
    "Need the same job across a whole folder, or a vector tool instead? The rest of the family shares the same local-first foundation."
};
</script>
