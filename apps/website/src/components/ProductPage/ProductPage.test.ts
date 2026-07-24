import { mount, RouterLinkStub } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import ProductPage from "./ProductPage.vue";
import type { ProductPageData } from "./ProductPage.model";

vi.mock("@sil/ui", () => ({
  Button: { props: ["to", "href", "variant"], template: "<a :href=\"href ?? to\"><slot /></a>" },
  Icon: { props: ["name", "size"], template: "<i :data-icon=\"name\" />" }
}));

const data: ProductPageData = {
  id: "fekthor",
  name: "Fekthor",
  icon: "/media/brand/fekthor.svg",
  eyebrow: "Native macOS vector editor",
  tagline: "Vectors, built for icon sets.",
  lead: "A workspace-first vector editor for whole icon sets.",
  chips: ["macOS", "Fully local"],
  actions: [
    { label: "Get notified", to: "mailto:hello@hakobs.com", external: true },
    { label: "See all apps", to: "/#apps", variant: "outline" }
  ],
  features: [{ title: "Trace, done right", description: "Editable centreline strokes." }],
  sections: [
    { eyebrow: "Icon-set workflow", title: "Your folder is the project.", bullets: ["Searchable gallery"] }
  ]
};

const mountPage = () => mount(ProductPage, { props: { data }, global: { stubs: { RouterLink: RouterLinkStub } } });

describe("ProductPage", () => {
  it("renders the hero copy, chips, and actions from the config", () => {
    const text = mountPage().text();

    expect(text).toContain("Native macOS vector editor");
    expect(text).toContain("Vectors, built for icon sets.");
    expect(text).toContain("A workspace-first vector editor for whole icon sets.");
    expect(text).toContain("macOS");
    expect(text).toContain("Fully local");
    expect(text).toContain("Get notified");
    expect(text).toContain("See all apps");
  });

  it("renders features and sections and looks up the registry status by id", () => {
    const text = mountPage().text();

    expect(text).toContain("Trace, done right");
    expect(text).toContain("Editable centreline strokes.");
    expect(text).toContain("Your folder is the project.");
    expect(text).toContain("Searchable gallery");
    expect(text).toContain("In development");
  });

  it("scopes the accent modifier to the app and cross-links every sibling app", () => {
    const wrapper = mountPage();

    expect(wrapper.classes()).toContain("product-page--fekthor");
    const familyLinks = wrapper.findAllComponents(RouterLinkStub);
    expect(familyLinks.map((link) => link.props("to"))).toEqual(["/imagekid", "/upscale", "/cutout"]);
    expect(wrapper.find(".product-page__family-card--upscale").exists()).toBe(true);
  });
});
