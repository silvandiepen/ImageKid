import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";

import ImageKidMark from "./ImageKidMark.vue";

describe("ImageKidMark", () => {
  it("uses the requested accessible title and size", () => {
    const wrapper = mount(ImageKidMark, { props: { size: 40, title: "ImageKid mark" } });
    expect(wrapper.attributes("width")).toBe("40");
    expect(wrapper.attributes("aria-label")).toBe("ImageKid mark");
    expect(wrapper.html()).toContain("currentColor");
  });
});
