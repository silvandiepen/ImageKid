export interface ProductPreviewProps {
  compact?: boolean;
}

export interface ProductPreviewTool {
  label: string;
  icon: string;
  active?: boolean;
}

export const productPreviewTools: ProductPreviewTool[] = [
  { label: "View", icon: "media/image" },
  { label: "Pick", icon: "ui/pointer-arrow", active: true },
  { label: "Crop", icon: "ui/pathfinder-crop" },
  { label: "Draw", icon: "ui/paint-brush" },
  { label: "Text", icon: "ui/text-bold" },
  { label: "Resize", icon: "arrows/arrow-out-center" },
  { label: "Export", icon: "arrows/arrow-download" }
];
