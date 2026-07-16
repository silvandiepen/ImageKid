<template>
  <DocsShell>
    <div :class="bemm()">
      <p :class="bemm('eyebrow')">Architecture</p>
      <h1 :class="bemm('title')">A native app and a static product site.</h1>
      <h2 :class="bemm('heading')">Monorepo boundaries</h2>
      <p :class="bemm('copy')"><code :class="bemm('code')">apps/native-macos</code> owns the Swift package and native product behavior. <code :class="bemm('code')">apps/website</code> owns this Vue SPA and public documentation. Future reusable code belongs in <code :class="bemm('code')">packages</code>. Apps may depend on packages, never on one another.</p>
      <h2 :class="bemm('heading')">Native media model</h2>
      <p :class="bemm('copy')">Each SwiftUI window creates and owns its own media session model. Focused scene commands target that window's model. Image transforms and annotations use orientation-normalised media coordinates so viewport pan and zoom do not alter exported geometry. Image export renders from source media and current edit state, not from a screenshot of the window.</p>
      <h2 :class="bemm('heading')">Apple frameworks</h2>
      <ul :class="bemm('list')">
        <li :class="bemm('list-item')">SwiftUI and AppKit provide the application, windows, menus, pasteboard, and file panels.</li>
        <li :class="bemm('list-item')">AVFoundation and AVKit provide current local video loading and playback.</li>
        <li :class="bemm('list-item')">Core Image and Image I/O support full-resolution image rendering and formats.</li>
      </ul>
      <h2 :class="bemm('heading')">Website</h2>
      <p :class="bemm('copy')">Vue 3, Vue Router, strict TypeScript, Vite, <code :class="bemm('code')">@sil/ui</code>, <code :class="bemm('code')">bemm</code>, and <code :class="bemm('code')">open-icon</code> compile to static assets for Cloudflare Pages. The website has no runtime backend.</p>
      <h2 :class="bemm('heading')">Privacy boundary</h2>
      <p :class="bemm('copy')">The native app performs processing locally and has no account, analytics, ads, cloud fallback, or runtime download. The static website does not receive your media.</p>
    </div>
  </DocsShell>
</template>

<script setup lang="ts">
import { useBemm } from "bemm";
import DocsShell from "../components/DocsShell";

const bemm = useBemm("architecture-page", { includeBaseClass: true });
</script>
