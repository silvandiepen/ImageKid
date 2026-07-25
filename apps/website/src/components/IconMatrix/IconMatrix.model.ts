// Data for the containers-and-partials illustration on the Fekthor product
// page. open-icon ships several families where one base shape carries a small
// badge — folder/folder-check, file/file-star, and so on — which is exactly
// the container-plus-partial idea, so the matrix is built from real glyphs
// rather than mocked-up boxes.

export interface IconMatrixItem {
  /** open-icon name for the standalone glyph. */
  icon: string;
  /** Slug used to build the composed icon name, and shown as the label. */
  name: string;
}

export interface IconMatrixProps {
  containers?: IconMatrixItem[];
  partials?: IconMatrixItem[];
  /** Milliseconds each cell stays highlighted; ignored under reduced motion. */
  interval?: number;
}

export const iconMatrixContainers: IconMatrixItem[] = [
  { icon: "ui/folder", name: "folder" },
  { icon: "ui/file", name: "file" },
  { icon: "ui/note", name: "note" },
  { icon: "ui/talk", name: "talk" }
];

export const iconMatrixPartials: IconMatrixItem[] = [
  { icon: "ui/add-m", name: "add" },
  { icon: "ui/check-m", name: "check" },
  { icon: "ui/star-m", name: "star" },
  { icon: "ui/user", name: "user" }
];

/** The composed glyph a container/partial pair resolves to, e.g. "ui/folder-check". */
export const composedIconName = (container: IconMatrixItem, partial: IconMatrixItem): string =>
  `ui/${container.name}-${partial.name}`;
