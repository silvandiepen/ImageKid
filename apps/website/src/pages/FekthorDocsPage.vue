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

      <h2 :class="bemm('heading')">How to: turn a logo into an SVG</h2>
      <ol :class="bemm('steps')">
        <li>Drag the PNG or JPEG anywhere onto the Fekthor window. Tracing starts on the drop — there is no mode to enter first.</li>
        <li>Pick a trace mode. Smart guesses; Strokes is right for line art; Shapes for solid logos; Gradient for soft fills.</li>
        <li>Check the score. Fekthor renders your vectors back and compares them to the original, so you can see how close it landed.</li>
        <li>Clean up the paths. Anchors, handles, break and merge — all the usual editing applies to the result.</li>
        <li><kbd>⌘S</kbd> to save. You get plain SVG.</li>
      </ol>

      <h2 :class="bemm('heading')">How to: keep 200 icons consistent</h2>
      <ol :class="bemm('steps')">
        <li>Put the SVGs in a folder, with subfolders for categories.</li>
        <li><kbd>⇧⌘O</kbd> and choose that folder. Fekthor writes a small <code>.fekthor</code> workfile beside your icons and leaves the icons alone.</li>
        <li>The gallery lays itself out. Subfolders became your categories; everything is searchable and renameable.</li>
        <li>Drop a PNG into the workspace and it traces straight into a new entry.</li>
      </ol>

      <h2 :class="bemm('heading')">How to: recolour a whole set at once</h2>
      <ol :class="bemm('steps')">
        <li>Open Style Tokens with <kbd>⇧⌘K</kbd>.</li>
        <li>Add a token — a name and a colour, say <code>outline = #010101</code>.</li>
        <li>It binds by matching the colour, not by node IDs, so it finds every shape painted that colour anywhere in the set. Icons you drew long before the token existed are included.</li>
        <li>Change the token's value. Every bound paint is rewritten across the workspace; everything unbound round-trips untouched.</li>
      </ol>

      <h2 :class="bemm('heading')">How to: build one badge into forty containers</h2>
      <ol :class="bemm('steps')">
        <li>Mark an icon as a container and give it a slot.</li>
        <li>Mark the icon that goes inside as a partial.</li>
        <li>Choose the fit per slot: contain, cover, stretch, or centred at natural size.</li>
        <li>Turn on Preview Composed Icons (<kbd>⌥⌘P</kbd>) to see the combinations in the gallery. They are previews — nothing is on disk yet.</li>
        <li>Export the matrix in one pass when you are happy.</li>
      </ol>

      <h2 :class="bemm('heading')">How to: animate an icon</h2>
      <ol :class="bemm('steps')">
        <li>Open the animation library with <kbd>⌥⌘K</kbd> and define the animation once.</li>
        <li>Select a shape — or the whole icon — and apply it. It binds with a marker class, the same idea as the style tokens.</li>
        <li>Preview on the timeline with <kbd>⌥⌘T</kbd>.</li>
        <li>Save. The keyframes ship inside the SVG, namespaced by icon name so nothing collides. No runtime, no JavaScript.</li>
      </ol>

      <h2 :class="bemm('heading')">How to: export for someone else's spec</h2>
      <ol :class="bemm('steps')">
        <li>Open Export Profiles with <kbd>⇧⌘E</kbd>.</li>
        <li>Build a named profile: outline strokes, flatten, fit to a box, recolour.</li>
        <li>Run it over a category or the whole library.</li>
        <li>Your editable source is untouched — every action happens against a copy.</li>
      </ol>

      <h2 :class="bemm('heading')">Grid, snapping and guides</h2>
      <p :class="bemm('copy')">Icon work lives on a grid, so the grid is not an afterthought. Toggle its visibility, snap to it, and snap to points — dragged anchors and drawn shapes magnet onto other shapes' anchors and bounds. Point snapping (<kbd>⌥⌘'</kbd>) is an editor habit and persists globally; grid spacing belongs to the workspace and travels with the workfile.</p>

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
