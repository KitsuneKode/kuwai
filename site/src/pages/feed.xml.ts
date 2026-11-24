import rss from "@astrojs/rss";
import { getCollection } from "astro:content";
import type { APIContext } from "astro";

export async function GET(context: APIContext) {
  const releases = (await getCollection("releases")).sort(
    (a, b) => b.data.date.getTime() - a.data.date.getTime()
  );

  return rss({
    title: "kuwai Releases and Engineering Notes",
    description: "Release history and design-system milestones for kuwai, the liquid-glass Hyprland desktop built for coding agents.",
    site: context.site ?? "https://kuwai.kitsunekode.in",
    trailingSlash: false,
    items: releases.map((entry) => ({
      title: entry.data.title,
      pubDate: entry.data.date,
      description: entry.data.summary,
      categories: [entry.data.category],
      link: `/changelog/#${entry.data.slugId}`
    })),
    customData: `<language>en-us</language><atom:link href="https://kuwai.kitsunekode.in/feed.xml" rel="self" type="application/rss+xml"/>`,
    xmlns: {
      atom: "http://www.w3.org/2005/Atom"
    }
  });
}
