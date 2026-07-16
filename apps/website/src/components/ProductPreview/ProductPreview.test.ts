import { mount } from "@vue/test-utils";
import { getIcon } from "open-icon";
import { describe, expect, it, vi } from "vitest";
import ProductPreview from "./ProductPreview.vue";
import { productPreviewTools } from "./ProductPreview.model";

vi.mock("@sil/ui", () => ({ Icon: { template: "<i />" } }));

describe("ProductPreview", () => {
  it("labels the preview as the current source-build representation", () => {
    const text = mount(ProductPreview).text();

    expect(text).toContain("Current source build");
    expect(text).toContain("Interface representation");
    expect(text).toContain("Pick Colour tool active");
  });

  it("shows the source-faithful colour panel and complete native toolbar", () => {
    const text = mount(ProductPreview).text();

    expect(text).toContain("Picked Colours");
    expect(text).toContain("2 saved");
    expect(text).toContain("#315FDB");
    expect(text).toContain("View");
    expect(text).toContain("Pick");
    expect(text).toContain("Crop");
    expect(text).toContain("Draw");
    expect(text).toContain("Text");
    expect(text).toContain("Resize");
    expect(text).toContain("Export");
  });

  it("uses icon names that resolve through open-icon", () => {
    productPreviewTools.forEach((tool) => {
      expect(getIcon(tool.icon), `${tool.label} icon should resolve`).not.toBeNull();
    });
  });
});
