// The ImageKid app family. Drives the homepage app grid, the product-page
// hero/cross-links, and the footer. One entry per shipping (or upcoming) app.

export interface AppMeta {
  id: string;
  name: string;
  /** Short H2-level line for cards. */
  tagline: string;
  /** One or two sentences for cards. */
  summary: string;
  /** Path to the rounded-square icon in /public/media/brand. */
  icon: string;
  /** Brand accent, used as --app-accent on product pages and cards. */
  accent: string;
  /** Route to the product page. */
  to: string;
  /** Availability label, e.g. "Coming to the App Store". */
  status: string;
  /** Where it runs, e.g. "macOS · iPad · iPhone". */
  platforms: string;
  /** True for the two flagship apps (ImageKid, Fekthor). */
  flagship: boolean;
}

export const apps: AppMeta[] = [
  {
    id: "imagekid",
    name: "ImageKid",
    tagline: "The complete local image editor.",
    summary:
      "Remove backgrounds, enhance and upscale, crop, annotate, and export — all on your device, no subscription.",
    icon: "/media/brand/imagekid.svg",
    accent: "#315fdb",
    to: "/imagekid",
    status: "Coming to the App Store",
    platforms: "macOS · iPad · iPhone",
    flagship: true
  },
  {
    id: "fekthor",
    name: "Fekthor",
    tagline: "A vector editor built for icon sets.",
    summary:
      "The basics of Illustrator, but better — trace, edit, and batch-export clean SVGs from a folder of icons.",
    icon: "/media/brand/fekthor.svg",
    accent: "#6c5cf0",
    to: "/fekthor",
    status: "In development",
    platforms: "macOS",
    flagship: true
  },
  {
    id: "upscale",
    name: "ImageKid Upscale",
    tagline: "Batch upscaling, done locally.",
    summary:
      "Drop in a folder, pick a scale, and enlarge every image on-device. Pay once, keep using it.",
    icon: "/media/brand/upscale.svg",
    accent: "#0e9a83",
    to: "/upscale",
    status: "Coming soon",
    platforms: "macOS",
    flagship: false
  },
  {
    id: "cutout",
    name: "ImageKid Cutout",
    tagline: "Batch background removal.",
    summary:
      "Drop product shots, portraits, or generated assets and get clean transparent PNGs — no service fees.",
    icon: "/media/brand/cutout.svg",
    accent: "#e0552a",
    to: "/cutout",
    status: "Coming soon",
    platforms: "macOS",
    flagship: false
  }
];

export const appById = (id: string): AppMeta | undefined => apps.find((a) => a.id === id);
export const otherApps = (id: string): AppMeta[] => apps.filter((a) => a.id !== id);
