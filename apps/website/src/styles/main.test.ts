import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const stylesheet = readFileSync(`${process.cwd()}/src/styles/main.scss`, "utf8");

const relativeLuminance = (hex: string): number => {
  const channels = hex.slice(1).match(/.{2}/g)?.map((channel) => Number.parseInt(channel, 16) / 255) ?? [];
  const [red = 0, green = 0, blue = 0] = channels.map((channel) =>
    channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4
  );

  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
};

const contrastRatio = (first: string, second: string): number => {
  const [lighter, darker] = [relativeLuminance(first), relativeLuminance(second)].sort((a, b) => b - a);
  return (lighter + 0.05) / (darker + 0.05);
};

describe("responsive layout safeguards", () => {
  it("undoes the shared UI viewport scroll lock", () => {
    expect(stylesheet).toMatch(/html\s*\{[^}]*height:\s*initial\s*!important/s);
    expect(stylesheet).toMatch(/body\s*\{[^}]*height:\s*auto\s*!important/s);
    expect(stylesheet).toMatch(/body\s*\{[^}]*display:\s*block\s*!important/s);
  });

  it("does not force a viewport-height hero or hide native tools on mobile", () => {
    expect(stylesheet).not.toContain("min-height: 72vh");
    expect(stylesheet).not.toMatch(/product-preview[\s\S]*tool--optional[^{]*\{[^}]*display:\s*none/);
  });

  it("uses compact mobile section rhythm and accessible header targets", () => {
    expect(stylesheet).toMatch(/@media \(max-width: 640px\)[\s\S]*\.home-page \{ gap: var\(--space-xl\); \}/);
    expect(stylesheet).toMatch(/\.home-page__hero \{ gap: var\(--space-l\);/);
    expect(stylesheet).toMatch(/\.pill-header__toggle, \.pill-header__action--icon-only \{ min-width: 44px; width: 44px; min-height: 44px; height: 44px; \}/);
  });

  it("keeps the active preview tool above WCAG AA contrast", () => {
    const primary = stylesheet.match(/"primary":\s*(#[\da-f]{6})/i)?.[1];
    const light = stylesheet.match(/"light":\s*(#[\da-f]{6})/i)?.[1];

    expect(primary).toBeDefined();
    expect(light).toBeDefined();
    expect(stylesheet).toMatch(/&__tool--active \{ background: var\(--color-primary\); color: var\(--color-light\); \}/);
    expect(contrastRatio(primary!, light!)).toBeGreaterThanOrEqual(4.5);
  });
});
