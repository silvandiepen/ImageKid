import { mount, RouterLinkStub } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import SiteFooter from "./SiteFooter.vue";

vi.mock("@sil/ui", () => ({ Icon: { props: ["name", "size"], template: "<i :data-icon=\"name\" />" } }));

describe("SiteFooter", () => {
  it("links every mandatory public page", () => {
    const wrapper = mount(SiteFooter, { global: { stubs: { RouterLink: RouterLinkStub } } });
    expect(wrapper.text()).toContain("Support");
    expect(wrapper.text()).toContain("Privacy");
    expect(wrapper.text()).toContain("Terms");
  });
});
