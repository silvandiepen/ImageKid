export interface ProductAction {
  label: string;
  to: string;
  variant?: "primary" | "outline";
  external?: boolean;
}

export interface ProductFeature {
  title: string;
  description: string;
}

export interface ProductSection {
  eyebrow: string;
  title: string;
  copy?: string;
  bullets?: string[];
  image?: string;
  imageAlt?: string;
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
  heroImageAlt?: string;
  featuresTitle?: string;
  featuresEyebrow?: string;
  features?: ProductFeature[];
  sections?: ProductSection[];
  closingTitle?: string;
  closingCopy?: string;
}
