import { beforeEach, describe, expect, it, vi } from "vitest";

beforeEach(() => {
  vi.restoreAllMocks();
  vi.resetModules();
  localStorage.clear();
  document.documentElement.removeAttribute("data-theme");
  document.documentElement.removeAttribute("data-color-mode");
});

describe("useColorMode", () => {
  it("sets both document theme attributes", async () => {
    const { useColorMode } = await import("./useColorMode");
    useColorMode().setMode("dark");
    expect(document.documentElement.dataset.theme).toBe("dark");
    expect(document.documentElement.dataset.colorMode).toBe("dark");
    expect(localStorage.getItem("imagekid-color-mode")).toBe("dark");
  });

  it("still applies a theme when storage is unavailable", async () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new DOMException("Storage denied", "SecurityError");
    });
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new DOMException("Storage denied", "SecurityError");
    });

    const { useColorMode } = await import("./useColorMode");
    useColorMode().setMode("dark");

    expect(document.documentElement.dataset.theme).toBe("dark");
    expect(document.documentElement.dataset.colorMode).toBe("dark");
  });
});
