import { beforeEach, describe, expect, it, vi } from "vitest";

const storageKey = "imagekid-color-mode";

function createStorage(): Storage {
  const values = new Map<string, string>();
  return {
    get length() {
      return values.size;
    },
    clear() {
      values.clear();
    },
    getItem(key: string) {
      return values.get(key) ?? null;
    },
    key(index: number) {
      return Array.from(values.keys())[index] ?? null;
    },
    removeItem(key: string) {
      values.delete(key);
    },
    setItem(key: string, value: string) {
      values.set(key, value);
    }
  };
}

beforeEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  vi.resetModules();
  vi.stubGlobal("localStorage", createStorage());
  document.documentElement.removeAttribute("data-theme");
  document.documentElement.removeAttribute("data-color-mode");
});

describe("useColorMode", () => {
  it("sets both document theme attributes", async () => {
    const { useColorMode } = await import("./useColorMode");
    useColorMode().setMode("dark");
    expect(document.documentElement.dataset.theme).toBe("dark");
    expect(document.documentElement.dataset.colorMode).toBe("dark");
    expect(localStorage.getItem(storageKey)).toBe("dark");
  });

  it("still applies a theme when storage is unavailable", async () => {
    vi.spyOn(localStorage, "getItem").mockImplementation(() => {
      throw new DOMException("Storage denied", "SecurityError");
    });
    vi.spyOn(localStorage, "setItem").mockImplementation(() => {
      throw new DOMException("Storage denied", "SecurityError");
    });

    const { useColorMode } = await import("./useColorMode");
    useColorMode().setMode("dark");

    expect(document.documentElement.dataset.theme).toBe("dark");
    expect(document.documentElement.dataset.colorMode).toBe("dark");
  });
});
