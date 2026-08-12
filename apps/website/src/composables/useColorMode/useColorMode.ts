import { computed, ref } from "vue";

import type { ColorMode, ColorModeState, ResolvedTheme } from "./useColorMode.model";

const STORAGE_KEY = "imagekid-color-mode";
const modes: ColorMode[] = ["light", "dark", "auto"];
const isColorMode = (value: string | null): value is ColorMode => value !== null && modes.includes(value as ColorMode);

function readStoredMode(): ColorMode {
  try {
    const stored = globalThis.localStorage?.getItem(STORAGE_KEY) ?? null;
    return isColorMode(stored) ? stored : "light";
  } catch {
    return "light";
  }
}

function storeMode(value: ColorMode): void {
  try {
    globalThis.localStorage?.setItem(STORAGE_KEY, value);
  } catch {
    // Theme changes still apply when storage is unavailable.
  }
}

const initial = readStoredMode();
const mode = ref<ColorMode>(initial);
const prefersDark = ref(globalThis.matchMedia?.("(prefers-color-scheme: dark)").matches ?? false);

const theme = computed<ResolvedTheme>(() => mode.value === "auto" ? (prefersDark.value ? "dark" : "light") : mode.value);

// Mobile browsers paint their own chrome from this, so it has to follow the
// resolved theme rather than sit on the light ground it was authored against.
const themeColors: Record<ResolvedTheme, string> = { light: "#f8f8f6", dark: "#151820" };

function applyThemeColor(): void {
  const meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
  if (meta) meta.content = themeColors[theme.value];
}

function apply(): void {
  document.documentElement.dataset.colorMode = mode.value;
  document.documentElement.dataset.theme = theme.value;
  applyThemeColor();
}

function setMode(value: ColorMode): void {
  mode.value = value;
  storeMode(value);
  apply();
}

function cycleMode(): void {
  setMode(modes[(modes.indexOf(mode.value) + 1) % modes.length] ?? "light");
}

const query = globalThis.matchMedia?.("(prefers-color-scheme: dark)");
query?.addEventListener("change", (event) => {
  prefersDark.value = event.matches;
  if (mode.value === "auto") apply();
});
apply();

export function useColorMode(): ColorModeState {
  return { mode, theme, setMode, cycleMode };
}
