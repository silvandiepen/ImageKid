export interface ProductAction {
  label: string;
  to: string;
  variant?: "primary" | "outline";
  external?: boolean;
}

export interface ProductFeature {
  title: string;
  description: string;
  /** open-icon name shown above the title, e.g. "ui/pointer-pen". */
  icon?: string;
}

/** Live open-icon illustration rendered in place of a section's image. */
export type ProductSectionVisual = "icon-gallery" | "icon-matrix";

export interface ProductSection {
  eyebrow: string;
  title: string;
  copy?: string;
  bullets?: string[];
  image?: string;
  imageAlt?: string;
  /** Rendered instead of the image; takes precedence over both image and character. */
  visual?: ProductSectionVisual;
  /** Which side the media sits on (default right). */
  imageSide?: "left" | "right";
  /** Background tint step 1–5 (darker = higher). */
  tone?: number;
}

export interface ProductPageData {
  /** App id from the registry, used for cross-links, status, and the per-app accent modifier. */
  id: string;
  name: string;
  icon: string;
  eyebrow: string;
  /** H1. */
  tagline: string;
  lead: string;
  chips: string[];
  actions: ProductAction[];
  /** Optional hero screenshot; when absent the icon panel is shown. */
  heroImage?: string;
  /** Cut-out character render; when set, the hero uses AppHero. */
  character?: string;
  heroImageAlt?: string;
  featuresTitle?: string;
  featuresEyebrow?: string;
  features?: ProductFeature[];
  sections?: ProductSection[];
  closingTitle?: string;
  closingCopy?: string;
}
