<template>
  <ProductPage :data="data" />
</template>

<script setup lang="ts">
import ProductPage from "../components/ProductPage";
import type { ProductPageData } from "../components/ProductPage";
import { appById } from "../data/apps";

const meta = appById("fekthor")!;
const data: ProductPageData = {
  id: meta.id,
  name: meta.name,
  character: "/media/character/fekthor.png",
  heroImage: "/media/fekthor/home.jpg",
  icon: meta.icon,
  eyebrow: "Native macOS vector editor",
  tagline: "The basics of Illustrator, but better.",
  lead:
    "Fekthor is a native vector editor built around the job Illustrator makes hard: whole icon sets. Draw and edit real vectors, trace raster art into clean editable paths, and export outlined SVGs across a folder — all local, all instant, no subscription.",
  chips: ["macOS", "Clean, git-diffable SVG", "Fully local"],
  actions: [
    { label: "Get notified", to: "mailto:hello@hakobs.com?subject=Fekthor", variant: "primary", external: true },
    { label: "See all apps", to: "/#apps", variant: "outline" }
  ],
  featuresEyebrow: "Why it's different",
  featuresTitle: "A vector editor that thinks in sets.",
  features: [
    { title: "Trace, done right", description: "Turn raster art into editable vectors — real centreline strokes with width, caps, and joins, not dead outlines around every dark pixel." },
    { title: "A real editor", description: "Anchors, handles, break/merge, layers, fill and stroke styles, gradients, transforms, and undo — the fundamentals, native and fast." },
    { title: "Icon sets first", description: "A folder-backed workspace lays out your icons in an auto-arranged, searchable gallery grouped by category. No artboard wrangling." },
    { title: "Design tokens", description: "Define colours, stroke styles, and radii once. Edit a token and every bound SVG on disk is rewritten — the whole set updates at once." },
    { title: "Export profiles", description: "Named, non-destructive pipelines: outline strokes, flatten, fit, recolour, and batch-export a whole library — without touching your editable source." },
    { title: "Clean SVG format", description: "Files stay plain, resolved SVG — git-diffable and drop-in for web projects. A .fekthor workfile holds the project meta, never polluting the SVG." }
  ],
  sections: [
    {
      eyebrow: "The flagship feature",
      title: "Tracing that produces vectors you can actually edit.",
      copy:
        "Smart, Strokes, Shapes, and Gradient modes classify your image and emit typed geometry — real strokes where the source has strokes, filled shapes where it's solid. Every conversion is scored against the original with a render-back comparison.",
      bullets: ["Centreline strokes with editable width", "Hybrid stroke + fill output", "Low path count, meaningful Béziers", "Scored against the source (exact-match %, PSNR)"],
      imageSide: "right",
      tone: 1
    },
    {
      eyebrow: "Icon-set workflow",
      title: "Your folder is the project.",
      copy:
        "Point Fekthor at a folder of icons and it becomes a workspace: categories are subfolders, the gallery arranges itself, and everything is searchable and renameable. Drop a PNG in and it traces into a new entry.",
      bullets: ["Folder- and category-backed", "Auto-laid-out, searchable gallery", "Drop-to-trace into the set"],
      imageSide: "left",
      tone: 2
    },
    {
      eyebrow: "Non-destructive by design",
      title: "Author as strokes, export as anything.",
      copy:
        "Icons stay editable strokes and lines; outlining, flattening, resizing, and recolouring happen at export against a copy. Run a profile over a whole category and get deterministic, cleanly-named output — the source is never destroyed.",
      bullets: ["Outline / flatten / fit / recolour actions", "Batch a library or a category", "Deterministic output naming"],
      imageSide: "right",
      tone: 3
    }
  ],
  closingTitle: "Made by the people behind ImageKid.",
  closingCopy:
    "Fekthor shares ImageKid's native, local-first foundation and its shared UI toolkit — different medium, same principles."
};
</script>
