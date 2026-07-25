import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import IconGallery from "./IconGallery.vue";
import { iconGalleryCategories } from "./IconGallery.model";

vi.mock("@sil/ui", () => ({ Icon: { props: ["name", "size"], template: "<i :data-icon=\"name\" />" } }));

const total = iconGalleryCategories.reduce((sum, category) => sum + category.entries.length, 0);

describe("IconGallery", () => {
  it("renders every icon in the workspace until a category is picked", async () => {
    const wrapper = mount(IconGallery);
    expect(wrapper.findAll(".icon-gallery__cell")).toHaveLength(total);
    expect(wrapper.text()).toContain(`${total} of ${total}`);

    const arrows = iconGalleryCategories.find((category) => category.id === "arrows")!;
    await wrapper.findAll(".icon-gallery__category").find((button) => button.text() === "arrows")!.trigger("click");

    expect(wrapper.findAll(".icon-gallery__cell")).toHaveLength(arrows.entries.length);
    expect(wrapper.text()).toContain(`${arrows.entries.length} of ${total}`);
  });

  it("names every entry after an open-icon glyph", () => {
    const wrapper = mount(IconGallery);
    const names = wrapper.findAll("[data-icon]").map((node) => node.attributes("data-icon"));
    // The folder glyph in the header plus one per cell.
    expect(names).toHaveLength(total + 1);
    expect(names.every((name) => name?.includes("/"))).toBe(true);
  });
});
