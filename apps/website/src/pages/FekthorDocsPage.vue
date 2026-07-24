<template>
  <DocsShell>
    <div :class="bemm()">
      <header :class="bemm('header')">
        <img :class="bemm('icon')" src="/media/brand/fekthor.png" alt="" width="72" height="72" />
        <div>
          <p :class="bemm('eyebrow')">Fekthor documentation</p>
          <h1 :class="bemm('title')">Everything Fekthor does.</h1>
        </div>
      </header>

      <p :class="bemm('lede')">A vector editor built around icon sets, with image tracing built in. Fekthor is local-first: it ships without a network entitlement, so nothing it does can reach the internet.</p>

      <figure :class="bemm('figure')">
        <img :class="bemm('shot')" src="/media/fekthor/home.jpg" alt="Fekthor's home screen with New File, New Workspace and Open File." loading="lazy" />
        <figcaption :class="bemm('caption')">Three ways in: a single file, a workspace, or an existing SVG.</figcaption>
      </figure>

      <h2 :class="bemm('heading')">Files and workspaces</h2>
      <p :class="bemm('copy')">A <strong>file</strong> is one icon — a blank 72×72 artboard that saves as plain SVG, readable by anything. A <strong>workspace</strong> is a whole library: a <code>.fekthor</code> workfile sitting over a folder of SVGs, which is what you want when an icon set needs to stay internally consistent. Create one with <kbd>⇧⌘O</kbd> to open, or from the home screen.</p>

      <h2 :class="bemm('heading')">Tracing an image</h2>
      <p :class="bemm('copy')">Drop a PNG or photo anywhere in the window and Fekthor enters tracing — it is a mode you arrive in, not a tool you launch. <kbd>⇧⌘T</kbd> does the same from the menu. Tracing converts the bitmap to editable paths you can then clean up with the normal editing tools.</p>

      <h2 :class="bemm('heading')">Editing paths</h2>
      <p :class="bemm('copy')">Select with <kbd>⌘A</kbd>, group and ungroup with <kbd>⌘G</kbd> and <kbd>⇧⌘G</kbd>. Arrow keys nudge the selected path point. Boolean path operations — unite, subtract, intersect, exclude — combine shapes, and alignment and distribution work on either the artboard (with one node selected) or the selection itself.</p>

      <h2 :class="bemm('heading')">Grid, snapping and guides</h2>
      <p :class="bemm('copy')">Icon work lives on a grid. Toggle its visibility, snap to it, and snap to points — dragged anchors and drawn shapes magnet onto other shapes' anchors and bounds. Point snapping (<kbd>⌥⌘'</kbd>) is an editor habit and persists globally; grid spacing belongs to the workspace and travels with the workfile.</p>

      <h2 :class="bemm('heading')">Style tokens</h2>
      <p :class="bemm('copy')">Named styles shared across a workspace, so a stroke weight or colour is defined once and every icon referencing it updates together. Open with <kbd>⇧⌘K</kbd>.</p>

      <h2 :class="bemm('heading')">Animations</h2>
      <p :class="bemm('copy')">Workspace-level animation definitions applied to selections, previewed on a timeline (<kbd>⌥⌘T</kbd>). Manage the library with <kbd>⌥⌘K</kbd>.</p>

      <h2 :class="bemm('heading')">Exporting</h2>
      <p :class="bemm('copy')">Export profiles (<kbd>⇧⌘E</kbd>) describe how a workspace leaves Fekthor — which icons, at what sizes, in what format. Single files export as SVG, PNG or PDF.</p>

      <h2 :class="bemm('heading')">Keyboard shortcuts</h2>
      <p :class="bemm('copy')">Generated from the app's own menu definitions, so this list matches what ships.</p>
      <ShortcutTable :sections="shortcuts.Fekthor" />
    </div>
  </DocsShell>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";
import DocsShell from "../components/DocsShell";
import ShortcutTable from "../components/ShortcutTable.vue";
import { shortcuts } from "../data/shortcuts";

const bemm = useBemm("fekthor-docs-page", { includeBaseClass: true });
</script>
