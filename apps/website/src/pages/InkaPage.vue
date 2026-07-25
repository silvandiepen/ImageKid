<template>
  <ProductPage :data="data" />
</template>

<script setup lang="ts">
import ProductPage from "../components/ProductPage";
import type { ProductPageData } from "../components/ProductPage";
import { appById } from "../data/apps";

const meta = appById("inka")!;
const data: ProductPageData = {
  id: meta.id,
  name: meta.name,
  icon: meta.icon,
  character: "/media/character/inka.png",
  eyebrow: "Drawing & illustration for Mac and iPad",
  tagline: "Drawing, with a serious brush engine.",
  lead:
    "Inka is built around one thing done properly: the brush. Pressure, tilt and velocity drive real dabs on a Metal canvas — the same engine on your Mac and your iPad — with layers, a spinnable canvas, and files that never leave your device.",
  chips: ["macOS · iPad", "One engine, both surfaces", "Never touches the network"],
  actions: [
    { label: "Get notified", to: "mailto:hello@hakobs.com?subject=Inka", variant: "primary", external: true },
    { label: "Read the docs", to: "/docs/inka", variant: "outline" }
  ],
  featuresEyebrow: "What it is",
  featuresTitle: "A real drawing app, not a toy canvas.",
  features: [
    { title: "Pressure brushes", icon: "ui/paint-brush", description: "Stamp-based dabs with pressure, tilt and velocity dynamics, paper grain, taper and jitter — five built-in brushes and an editor that exposes every parameter." },
    { title: "Layers", icon: "ui/layers", description: "Add, reorder, hide and set per-layer opacity. Strokes stay editable vectors; the canvas re-renders from the document, so nothing is baked until you export." },
    { title: "Erase & select", icon: "ui/eraser", description: "A true eraser through the same engine, plus a move tool that marquee-selects strokes and moves, scales or rotates them — non-destructively." },
    { title: "A canvas you can spin", icon: "arrows/rotate", description: "Pan, zoom, rotate and flip the canvas freely — with the pencil, the trackpad, or two fingers — and draw at any angle." },
    { title: "Colour, quickly", icon: "media/color-pallette", description: "A working palette, recent colours, and an eyedropper that samples straight off the canvas." },
    { title: "Stays on your device", icon: "misc/shield-check", description: "Inka ships without a network entitlement. Your work is `.inka` on your disk; export flat or per-layer PNGs whenever you want." }
  ],
  sections: [
    {
      eyebrow: "The brush engine",
      title: "The part everything else is built on.",
      copy:
        "Most of the work went into the brush. Inka resamples your stroke to an even spacing, then drives each dab through response curves for pressure, tilt and velocity — size, opacity, flow, rotation and hue all react. Procedural paper grain gives real media its tooth, and it matches exactly between the live GPU canvas and the CPU renderer that exports your file.",
      bullets: [
        "Pressure, tilt and velocity dynamics",
        "Procedural grain with GPU/CPU parity",
        "Taper, scatter, jitter, square or round tips",
        "A brush editor for every parameter, with a live preview"
      ],
      imageSide: "right",
      tone: 1
    },
    {
      eyebrow: "Hybrid document",
      title: "Strokes stay editable. Forever.",
      copy:
        "A stroke is stored as its spine plus the brush it used — not a flat splat of pixels. Change the brush, undo ten steps back, hide a layer or drop its opacity, and the canvas rebuilds itself from the document. Import a photo as a layer to trace over. Export bakes it, once, against a copy.",
      bullets: [
        "Vector-stroke layers, re-rendered on every change",
        "Import an image as a layer to reference or trace",
        "40 steps of undo, non-destructive throughout",
        "Open and save your own `.inka` files"
      ],
      imageSide: "left",
      tone: 2
    },
    {
      eyebrow: "Move, scale, rotate",
      title: "Grab what you drew and move it.",
      copy:
        "Marquee a set of strokes and a transform box appears — drag inside to move, a corner to scale, the handle to rotate. Because strokes are vectors, the transform re-flows the real geometry rather than smearing pixels, so it stays crisp and it stays undoable. On the Mac the arrow keys nudge; delete removes.",
      bullets: [
        "Marquee selection on the active layer",
        "Move, scale and rotate from one box",
        "Edits the vector strokes, not a raster copy",
        "Arrow-key nudge and delete on macOS"
      ],
      imageSide: "right",
      tone: 3
    },
    {
      eyebrow: "One engine, two surfaces",
      title: "The same app in your hand and on your desk.",
      copy:
        "Mac and iPad share the engine, the document and the floating tool panels — so a `.inka` file behaves the same everywhere. The iPad adds the gestures you already know: draw with the Pencil, two fingers to pan and pinch, twist to rotate, a two-finger tap to undo and three to redo.",
      bullets: [
        "Apple Pencil pressure, tilt and azimuth",
        "Two-finger pan / pinch / rotate, together",
        "Two-finger tap undo, three-finger redo",
        "The same brushes, layers and files as macOS"
      ],
      imageSide: "left",
      tone: 2
    },
    {
      eyebrow: "Export",
      title: "Get your work out, whole or in parts.",
      copy:
        "Export a flattened PNG, or one PNG per layer for handing off to another tool. Everything flattens through the exact same renderer the canvas uses, so what you export is what you drew — down to the grain.",
      bullets: [
        "Flattened PNG, or per-layer PNGs",
        "Exact CPU rasterizer — matches the canvas",
        "Your editable source is never destroyed",
        "No accounts, no cloud, no watermarks"
      ],
      imageSide: "right",
      tone: 3
    }
  ],
  closingTitle: "Same people. Same principles.",
  closingCopy:
    "Inka shares ImageKid's native foundation and its local-first stance — a serious drawing tool that keeps your work on your own machine."
};
</script>
