import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

const releases = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/releases" }),
  schema: z.object({
    title: z.string(),
    summary: z.string(),
    date: z.coerce.date(),
    category: z.string(),
    slugId: z.string()
  })
});

export const collections = { releases };
