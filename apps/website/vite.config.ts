import vue from "@vitejs/plugin-vue";
import { defineTheme, ui } from "@sil/ui/vite";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [
    vue(),
    ui({
      theme: defineTheme({
        palette: {
          "imagekid-blue": "#315fdb",
          "imagekid-ink": "#151820",
          "imagekid-paper": "#f8f8f6"
        },
        colors: {
          dark: "imagekid-ink",
          light: "imagekid-paper",
          primary: "imagekid-blue",
          secondary: "imagekid-blue",
          border: "imagekid-ink"
        },
        fonts: {
          body: "system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif",
          heading: "system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif",
          mono: "\"SF Mono\", Consolas, \"Liberation Mono\", monospace"
        }
      })
    })
  ]
});
