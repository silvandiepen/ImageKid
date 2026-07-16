import vue from "@vitejs/plugin-vue";
import { ui } from "@sil/ui/vite";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [
    vue(),
    ui()
  ]
});
