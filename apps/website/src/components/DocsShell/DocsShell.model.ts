export interface DocsNavItem {
  label: string;
  to: string;
  description: string;
  /** open-icon name shown before the label in the sidebar and index. */
  icon: string;
}

export const docsNavigation: DocsNavItem[] = [
  { label: "Getting started", to: "/docs/getting-started", icon: "misc/rocket", description: "Requirements, local tools, and Magic provider setup." },
  { label: "ImageKid", to: "/docs/imagekid", icon: "media/image", description: "Every ImageKid feature, with screenshots and the full shortcut list." },
  { label: "Fekthor", to: "/docs/fekthor", icon: "ui/vector-curve", description: "Files and workspaces, tracing, tokens, and the full shortcut list." },
  { label: "Inka", to: "/docs/inka", icon: "ui/paint-brush", description: "Brushes, layers, selection and transform, colour, canvas nav, and export." },
  { label: "Workflows", to: "/docs/workflows", icon: "ui/git-branch", description: "Opening, keyboard controls, image editing, and image export." },
  { label: "Architecture", to: "/docs/architecture", icon: "ui/layers-3", description: "Native app structure, edit state, rendering, and monorepo boundaries." },
  { label: "Roadmap", to: "/docs/roadmap", icon: "wayfinding/signpost", description: "Implemented, incomplete, and deferred work." }
];
