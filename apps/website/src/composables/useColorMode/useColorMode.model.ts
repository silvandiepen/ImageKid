export type ColorMode = "light" | "dark" | "auto";
export type ResolvedTheme = "light" | "dark";

export interface ColorModeState {
  mode: Readonly<import("vue").Ref<ColorMode>>;
  theme: Readonly<import("vue").Ref<ResolvedTheme>>;
  setMode: (mode: ColorMode) => void;
  cycleMode: () => void;
}
