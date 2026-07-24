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
  eyebrow: "Vector editor for Mac",
  tagline: "Vectors, without the ceremony.",
  lead:
    "Draw, trace and ship SVGs. Fekthor handles the everyday vector work without asking you to learn a workflow first — and it is very good at the one job nothing else handles well: a whole set of icons that has to stay consistent.",
  chips: ["macOS", "SVG you can read in a diff", "Never touches the network"],
  actions: [
    { label: "Get notified", to: "mailto:hello@hakobs.com?subject=Fekthor", variant: "primary", external: true },
    { label: "Read the docs", to: "/docs/fekthor", variant: "outline" }
  ],
  featuresEyebrow: "The basics, done properly",
  featuresTitle: "Everything you expect. Then the part nobody else does.",
  features: [
    { title: "Draw and edit", description: "Anchors, handles, break and merge, boolean operations, layers, gradients, transforms, undo. The fundamentals, native and quick." },
    { title: "Trace anything", description: "Drop in a logo, a screenshot, a scan. You get real editable paths — strokes with width where the original has strokes, not a dead outline around every dark pixel." },
    { title: "Snap to everything", description: "Grid, points, bounds, other shapes' anchors. Icon work lives on a grid, so the grid is not an afterthought." },
    { title: "Plain SVG out", description: "No wrapper format, no lock-in. Files stay readable SVG that diffs cleanly and drops straight into a web project." },
    { title: "Workspaces", description: "A folder of icons becomes a project. Categories are subfolders, the gallery lays itself out, everything is searchable." },
    { title: "Stays on your Mac", description: "Fekthor ships without a network entitlement. It could not phone home if it wanted to." }
  ],
  sections: [
    {
      eyebrow: "Vectorising",
      title: "Turn a logo into an SVG in about four seconds.",
      copy:
        "Point it at a PNG, a JPEG, a screenshot of a logo whose source went missing years ago. Fekthor classifies the image and emits typed geometry — strokes where there are strokes, shapes where it is solid — then scores the result against the original, so you know how close it landed instead of guessing.",
      bullets: [
        "Centreline strokes with editable width",
        "Low path count, Béziers that mean something",
        "Scored against the source",
        "Drop it on the window and it starts"
      ],
      image: "/media/fekthor/home.jpg",
      imageAlt: "Fekthor's home screen, where a drop starts a trace",
      imageSide: "right",
      tone: 1
    },
    {
      eyebrow: "Workspaces",
      title: "Your folder is the project.",
      copy:
        "Open a folder of SVGs and you have a workspace — a small .fekthor file alongside them holding the project meta, never polluting the icons themselves. Subfolders become categories. The gallery arranges itself. Drop a PNG in and it traces into a new entry.",
      bullets: [
        "Folder-backed, so your files stay yours",
        "Categories from subfolders, no configuration",
        "Searchable, renameable, auto-arranged",
        "The workfile never touches your SVG"
      ],
      imageSide: "left",
      tone: 2
    },
    {
      eyebrow: "Shared styles and tokens",
      title: "Change one colour. Watch two hundred icons follow.",
      copy:
        "A token is a named colour slot — outline, accent, whatever you call it. Here is the trick: tokens bind by matching the colour itself, not by node IDs. So they find every shape painted that colour anywhere in the set, including icons you drew long before the token existed. Change the value and every bound paint is rewritten. Everything else round-trips untouched.",
      bullets: [
        "Binds by colour, not by fragile IDs",
        "Works on icons drawn before the token existed",
        "Named classes shared across the workspace",
        "Everything unbound survives verbatim"
      ],
      image: "/media/accent/fekthor-portrait.jpg",
      imageAlt: "",
      imageSide: "right",
      tone: 3
    },
    {
      eyebrow: "Containers and partials",
      title: "One badge. Forty containers. One export.",
      copy:
        "Mark an icon as a container with a slot in it, mark another as a partial, and Fekthor composes them. Fit each partial into each slot — contain, cover, stretch or centred — and export the whole matrix at once. Composed icons are previews; nothing is written to disk until you say so.",
      bullets: [
        "Containers hold slots, partials fill them",
        "Contain, cover, stretch or centre per slot",
        "Preview the composed set before committing",
        "Export the whole matrix in one pass"
      ],
      imageSide: "left",
      tone: 1
    },
    {
      eyebrow: "Animation",
      title: "Icons that move, in the file itself.",
      copy:
        "Define an animation once in the workspace library, apply it to a selection or a whole icon, and it binds with a marker class. Keyframes are namespaced per icon so nothing collides. Preview it on the timeline, and it ships inside the SVG — no runtime, no JavaScript.",
      bullets: [
        "Workspace library plus file-local definitions",
        "Binds by marker class, like the tokens",
        "Keyframes namespaced per icon",
        "Timeline preview before you commit"
      ],
      imageSide: "right",
      tone: 2
    },
    {
      eyebrow: "Export",
      title: "Author as strokes. Ship whatever they asked for.",
      copy:
        "Outlining, flattening, fitting and recolouring all happen at export, against a copy. Run a named profile over a category or the whole library and get deterministic, cleanly-named output. Your editable source is never destroyed.",
      bullets: [
        "Named, repeatable export profiles",
        "Outline, flatten, fit, recolour",
        "Batch a category or the whole set",
        "The source survives every export"
      ],
      imageSide: "left",
      tone: 3
    }
  ],
  closingTitle: "Same people. Same principles.",
  closingCopy:
    "Fekthor shares ImageKid's native foundation and its local-first stance. Different medium, same refusal to upload your work anywhere."
};
</script>
