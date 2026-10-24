import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/postcss";

export default defineConfig({
  root: "github-pages-src",
  base: "/key-hand-review-ios/",
  publicDir: "../public",
  plugins: [react()],
  css: {
    postcss: {
      plugins: [tailwindcss()],
    },
  },
  build: {
    outDir: "../pages-dist",
    emptyOutDir: true,
  },
});
