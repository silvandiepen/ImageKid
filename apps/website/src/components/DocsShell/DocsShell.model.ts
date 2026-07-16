export interface DocsNavItem {
  label: string;
  to: string;
  description: string;
}

export const docsNavigation: DocsNavItem[] = [
  { label: "Getting started", to: "/docs/getting-started", description: "Requirements, build commands, and release boundary." },
  { label: "Workflows", to: "/docs/workflows", description: "Opening, keyboard controls, image editing, and image export." },
  { label: "Architecture", to: "/docs/architecture", description: "Native app structure, edit state, rendering, and monorepo boundaries." },
  { label: "Roadmap", to: "/docs/roadmap", description: "Implemented, incomplete, and deferred work." }
];
