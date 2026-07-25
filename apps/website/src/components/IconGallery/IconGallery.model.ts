// Data for the workspace-gallery illustration on the Fekthor product page.
// The icons are real open-icon glyphs, loaded at runtime by @sil/ui's Icon —
// the point of the section is that a folder of SVGs lays itself out, so the
// illustration is built from an actual icon set rather than a screenshot.

export interface IconGalleryEntry {
  /** open-icon name, e.g. "ui/folder". */
  icon: string;
  /** File name as it would sit on disk, without the extension. */
  name: string;
}

export interface IconGalleryCategory {
  /** Subfolder name — categories come from subfolders, so this is the label. */
  id: string;
  entries: IconGalleryEntry[];
}

export interface IconGalleryProps {
  /** Workspace folder name shown in the panel header. */
  folder?: string;
  categories?: IconGalleryCategory[];
}

export const iconGalleryCategories: IconGalleryCategory[] = [
  {
    id: "interface",
    entries: [
      { icon: "ui/settings", name: "settings" },
      { icon: "ui/dashboard", name: "dashboard" },
      { icon: "ui/window", name: "window" },
      { icon: "ui/grid", name: "grid" },
      { icon: "ui/layers-3", name: "layers" },
      { icon: "ui/swatches", name: "swatches" }
    ]
  },
  {
    id: "files",
    entries: [
      { icon: "ui/folder", name: "folder" },
      { icon: "ui/file", name: "file" },
      { icon: "ui/file-code", name: "file-code" },
      { icon: "ui/box", name: "box" },
      { icon: "ui/note", name: "note" },
      { icon: "ui/file-tray", name: "tray" }
    ]
  },
  {
    id: "arrows",
    entries: [
      { icon: "arrows/arrow-headed-up", name: "up" },
      { icon: "arrows/arrow-headed-right", name: "right" },
      { icon: "arrows/arrow-headed-down", name: "down" },
      { icon: "arrows/arrow-headed-reload-left-right", name: "reload" },
      { icon: "arrows/arrow-download", name: "download" },
      { icon: "arrows/arrow-upload", name: "upload" }
    ]
  },
  {
    id: "media",
    entries: [
      { icon: "media/image", name: "image" },
      { icon: "media/camera", name: "camera" },
      { icon: "media/video-camera", name: "video" },
      { icon: "media/music-note", name: "music" },
      { icon: "media/headphones", name: "audio" },
      { icon: "media/color-pallette", name: "palette" }
    ]
  }
];
