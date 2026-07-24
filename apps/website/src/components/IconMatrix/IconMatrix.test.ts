import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import IconMatrix from "./IconMatrix.vue";
import { iconMatrixContainers, iconMatrixPartials } from "./IconMatrix.model";

vi.mock("@sil/ui", () => ({ Icon: { props: ["name", "size"], template: "<i :data-icon=\"name\" />" } }));

const cells = iconMatrixContainers.length * iconMatrixPartials.length;

describe("IconMatrix", () => {
  it("composes every container with every partial", () => {
    const wrapper = mount(IconMatrix);
    const composed = wrapper.findAll(".icon-matrix__cell [data-icon]").map((node) => node.attributes("data-icon"));

    expect(composed).toHaveLength(cells);
    expect(composed).toContain("ui/folder-check");
    expect(composed).toContain("ui/talk-user");
  });

  it("highlights one cell together with its container and partial", () => {
    const wrapper = mount(IconMatrix);

    expect(wrapper.findAll(".icon-matrix__cell--active")).toHaveLength(1);
    expect(wrapper.findAll(".icon-matrix__head--active")).toHaveLength(2);
  });

  it("holds still when the visitor asked for reduced motion", () => {
    vi.stubGlobal("matchMedia", vi.fn(() => ({ matches: true })));
    const interval = vi.spyOn(globalThis, "setInterval");

    mount(IconMatrix);

    expect(interval).not.toHaveBeenCalled();
    interval.mockRestore();
    vi.unstubAllGlobals();
  });
});
