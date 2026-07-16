import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import ProductPreview from "./ProductPreview.vue";

describe("ProductPreview", () => {
  it("labels itself as an interface representation", () => {
    expect(mount(ProductPreview).text()).toContain("Interface representation");
  });
});
