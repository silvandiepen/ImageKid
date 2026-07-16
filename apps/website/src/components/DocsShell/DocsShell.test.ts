import { mount, RouterLinkStub } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import DocsShell from "./DocsShell.vue";

vi.mock("vue-router", async () => ({ RouterLink: RouterLinkStub, useRoute: () => ({ path: "/docs/workflows" }) }));
describe("DocsShell", () => {
  it("renders the complete docs index", () => {
    const wrapper = mount(DocsShell);
    expect(wrapper.text()).toContain("Getting started");
    expect(wrapper.text()).toContain("Architecture");
    expect(wrapper.text()).toContain("Roadmap");
  });
});
