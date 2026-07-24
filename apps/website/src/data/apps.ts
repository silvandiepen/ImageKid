// The ImageKid app family. Drives the homepage app grid, the product-page
// hero/cross-links, and the footer. One entry per shipping (or upcoming) app.

export interface AppMeta {
  id: string;
  name: string;
  /** Short H2-level line for cards. */
  tagline: string;
  /** One or two sentences for cards. */
  summary: string;
  /** Path to the shipping app icon, exported from the asset catalog. */
  icon: string;
  /** Large character render for the product-page hero. */
  hero: string;
  /** Project-colour name driving the page accent. */
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
    tagline: "Image editing that gets out of the way.",
    summary:
      "Cut the background, make it bigger, crop it, mark it up. All on your Mac, no subscription.",
    icon: "/media/brand/imagekid.png",
    hero: "/media/hero/imagekid.jpg",
    accent: "primary",
    to: "/imagekid",
    status: "Coming to the App Store",
    platforms: "macOS · iPad · iPhone",
    flagship: true
  },
  {
    id: "fekthor",
    name: "Fekthor",
    tagline: "Vectors, without the ceremony.",
    summary:
      "Draw and trace vectors, then keep a whole folder of icons consistent. Plain SVG out, nothing uploaded.",
    icon: "/media/brand/fekthor.png",
    hero: "/media/hero/fekthor.jpg",
    accent: "fekthor",
    to: "/fekthor",
    status: "In development",
    platforms: "macOS",
    flagship: true
  },
  {
    id: "upscale",
    name: "ImageKid Upscale",
    tagline: "Small pictures, made big.",
    summary:
      "Drop in a folder, pick a scale, and enlarge every image on-device. Pay once, keep using it.",
    icon: "/media/brand/upscale.png",
    hero: "/media/hero/upscale.jpg",
    accent: "upscale",
    to: "/upscale",
    status: "Coming soon",
    platforms: "macOS",
    flagship: false
  },
  {
    id: "cutout",
    name: "ImageKid Cutout",
    tagline: "Backgrounds, gone.",
    summary:
      "Drop product shots, portraits, or generated assets and get clean transparent PNGs — no service fees.",
    icon: "/media/brand/cutout.png",
    hero: "/media/hero/cutout.jpg",
    accent: "cutout",
    to: "/cutout",
    status: "Coming soon",
    platforms: "macOS",
    flagship: false
  }
];

export const appById = (id: string): AppMeta | undefined => apps.find((a) => a.id === id);
export const otherApps = (id: string): AppMeta[] => apps.filter((a) => a.id !== id);
