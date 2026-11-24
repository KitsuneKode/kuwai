import { defineConfig } from "astro/config";
import react from "@astrojs/react";
import sitemap from "@astrojs/sitemap";

export default defineConfig({
  site: "https://kuwai.kitsunekode.in",
  output: "static",
  compressHTML: true,
  integrations: [react(), sitemap()]
});
