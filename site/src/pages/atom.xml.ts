import { getCollection } from "astro:content";
import type { APIContext } from "astro";

function escapeXml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

export async function GET(context: APIContext) {
  const site = (context.site ?? new URL("https://kuwai.kitsunekode.in")).toString().replace(/\/$/, "");
  const releases = (await getCollection("releases")).sort(
    (a, b) => b.data.date.getTime() - a.data.date.getTime()
  );
  const updated = releases[0]?.data.date.toISOString() ?? new Date().toISOString();

  const entries = releases
    .map((entry) => {
      const link = `${site}/changelog#${entry.data.slugId}`;
      return [
        "  <entry>",
        `    <title>${escapeXml(entry.data.title)}</title>`,
        `    <link href="${link}"/>`,
        `    <id>${link}</id>`,
        `    <updated>${entry.data.date.toISOString()}</updated>`,
        `    <summary>${escapeXml(entry.data.summary)}</summary>`,
        "  </entry>"
      ].join("\n");
    })
    .join("\n");

  const body = `<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>kuwai Releases and Engineering Notes</title>
  <subtitle>Liquid-glass Hyprland desktop and Dynamic Island built for coding agents.</subtitle>
  <link href="${site}/atom.xml" rel="self" type="application/atom+xml"/>
  <link href="${site}/" rel="alternate" type="text/html"/>
  <id>${site}/</id>
  <updated>${updated}</updated>
  <icon>${site}/assets/brand/icon-192.png</icon>
  <author>
    <name>KitsuneKode</name>
    <uri>https://github.com/KitsuneKode/kuwai</uri>
  </author>
${entries}
</feed>
`;

  return new Response(body, {
    headers: { "Content-Type": "application/atom+xml; charset=utf-8" }
  });
}
