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
  eyebrow: "Native image editor for Mac, iPad & iPhone",
  tagline: "Image editing that gets out of the way.",
  lead:
    "Drop an image in. Cut the background, make it bigger, crop it, mark it up, send it on. No account, no subscription, no upload. The AI runs on your Mac, which is where your pictures already were.",
  chips: ["macOS 14 · iPadOS · iOS 17", "One app, all your devices", "Local-first processing"],
  actions: [
    { label: "Explore the features", to: "/features", variant: "primary" },
    { label: "Read the privacy note", to: "/privacy", variant: "outline" }
  ],
  character: "/media/character/imagekid.png",
  heroImage: "/media/app/workspace.jpg",
  heroImageAlt: "The ImageKid editor with an image open and the tool palette visible",
  featuresEyebrow: "In the box",
  featuresTitle: "A full editor, not a one-trick app.",
  features: [
    { title: "Remove backgrounds", description: "One tap and the subject is cut out. There is a fast built-in model, and a better one you can download for hair and other nightmares." },
    { title: "Enhance & upscale", description: "Quick, High or Max. Same size, 2× or 4×. You pick how good it needs to be; the app picks the model." },
    { title: "Crop & resize", description: "Exact pixels, locked ratios, drag handles. Crops stay reversible until you tell them not to be." },
    { title: "Rotate & flip", description: "Straighten, spin, mirror. Re-rendered clean every time, not nudged pixel by pixel." },
    { title: "Draw, text & colour", description: "Shapes, arrows, freehand, text. Pick colours straight off the image and keep them in a swatch list." },
    { title: "Private by default", description: "Everything local runs local. No account, no analytics, no tracking. Magic is the one exception, and only if you set it up." }
  ],
  sections: [
    {
      eyebrow: "Cut it out",
      title: "It gets the hair right.",
      copy:
        "One tap gives you an instant cut-out. If the shot is harder — flyaway hair, a busy background — grab the best-quality model, which also runs on your Mac. Then refine the mask by hand if you want the last word.",
      bullets: ["Built-in remover, no download", "Optional best-quality on-device model", "Manual refine brush"],
      image: "/media/app/background-refine.jpg",
      imageAlt: "Refining a background cut-out in ImageKid",
      imageSide: "right",
      tone: 1
    },
    {
      eyebrow: "Bigger & sharper",
      title: "Quality grades, not model names.",
      copy:
        "Nobody wants to choose between four checkpoints with version numbers. Pick Quick, High or Max. Keep the size or go 2× or 4×. The app works out the rest, on device.",
      bullets: ["Quick · High · Max grades", "Same size, 2×, or 4×", "Runs entirely on-device"],
      image: "/media/app/resize.jpg",
      imageAlt: "Resize and enhance controls in ImageKid",
      imageSide: "left",
      tone: 2
    },
    {
      eyebrow: "Everyday tools",
      title: "The boring bits, done well.",
      copy:
        "Crop to exact sizes. Add shapes and text. Sample a colour off the canvas. Every export is rendered fresh from your original plus your edits — never a lossy round-trip through a saved copy.",
      image: "/media/app/annotate.jpg",
      imageAlt: "Annotating an image in ImageKid",
      imageSide: "right",
      tone: 3
    },
    {
      eyebrow: "Magic",
      title: "Magic, and the honest asterisk.",
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
