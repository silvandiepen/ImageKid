export interface DocsNavItem {
  label: string;
  to: string;
  description: string;
}

export const docsNavigation: DocsNavItem[] = [
  { label: "Getting started", to: "/docs/getting-started", description: "Requirements, local tools, and Magic provider setup." },
  { label: "ImageKid", to: "/docs/imagekid", description: "Every ImageKid feature, with screenshots and the full shortcut list." },
  { label: "Fekthor", to: "/docs/fekthor", description: "Files and workspaces, tracing, tokens, and the full shortcut list." },
  { label: "Workflows", to: "/docs/workflows", description: "Opening, keyboard controls, image editing, and image export." },
  { label: "Architecture", to: "/docs/architecture", description: "Native app structure, edit state, rendering, and monorepo boundaries." },
  { label: "Roadmap", to: "/docs/roadmap", description: "Implemented, incomplete, and deferred work." }
];
