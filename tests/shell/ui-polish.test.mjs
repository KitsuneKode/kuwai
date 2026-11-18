// Shell-wide UI rules that each came from a real bug (2026-11-18).
//   bun test tests/shell/ui-polish.test.mjs
import { describe, expect, test } from "bun:test";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { functions } from "../helpers/qml.mjs";

const ROOT = new URL("../../", import.meta.url).pathname;
const qml = [];
(function walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p);
    else if (name.endsWith(".qml")) qml.push(p);
  }
})(join(ROOT, "shell"));
const read = (p) => readFileSync(p, "utf8");
const rel = (p) => relative(ROOT, p);
const code = (line) => line.replace(/\/\/.*$/, "");

describe("screen geometry", () => {
  const s = functions("shell/config/Theme.qml", ["screenSize"], { minScreen: 320 });
  test("an output reporting 0, NaN or nothing falls back", () => {
    expect(s.screenSize({ width: 0 }, "width", 7)).toBe(7);
    expect(s.screenSize({ height: NaN }, "height", 9)).toBe(9);
    expect(s.screenSize(null, "width", 5)).toBe(5);
    expect(s.screenSize({}, "height", 4)).toBe(4);
  });
  test("a real size is used as is", () => {
    expect(s.screenSize({ width: 2560 }, "width", 7)).toBe(2560);
    expect(s.screenSize({ height: 720 }, "height", 9)).toBe(720);
  });
  // The tooltip collapsed into a one-letter column from screen.width = 0.
  // Window sizes go through Theme.screenSize; the pointer zone may read the
  // raw value (0 means "not on this screen", which is right).
  test("no window size reads screen geometry straight", () => {
    const raw = /\b(modelData|screen|Screen)\??\.(width|height)\b/;
    const hits = [];
    for (const p of qml) {
      if (/config\/Theme\.qml$|components\/Tip\.qml$/.test(p)) continue;
      read(p).split("\n").forEach((line, i) => {
        const c = code(line);
        if (raw.test(c) && !/onThisScreen|inZone|localX/.test(c) && !/function inZone/.test(c))
          hits.push(`${rel(p)}:${i + 1}: ${c.trim()}`);
      });
    }
    expect(hits).toEqual([]);
  });
});

describe("waveforms", () => {
  // A Behavior restarted by every audio peak, plus a timer per bar, redrew
  // the surface on every frame while music played (IslandRest's notch was
  // fixed first; the hover view and the media panel kept the old pattern).
  const files = qml.filter((p) => /readonly property real liveH:/.test(read(p)));
  test("found the waveform surfaces", () => expect(files.length).toBeGreaterThanOrEqual(3));
  for (const p of files) {
    test(`${rel(p)}: live bars are set straight on one shared tick`, () => {
      const lines = read(p).split("\n");
      lines.forEach((line, i) => {
        if (!/readonly property real liveH:/.test(line)) return;
        const bar = lines.slice(i, i + 10).join("\n");
        const behavior = bar.match(/Behavior on height \{[^\n]*/);
        if (behavior) expect(behavior[0]).toContain("enabled:");
        expect(bar).not.toMatch(/\bTimer\s*\{/);
      });
    });
  }
});

describe("hover fills", () => {
  // Ten hand-typed greys (0.05–0.11) for the same job; Theme names them now.
  test("faint white hover fills come from Theme", () => {
    const faint = /(containsMouse|hovered)[^?]*\?\s*Qt\.rgba\(1,\s*1,\s*1,\s*0\.(0\d*|1([0-4]\d*)?)\)/;
    const hits = [];
    for (const p of qml) {
      if (/config\/Theme\.qml$/.test(p)) continue;
      read(p).split("\n").forEach((line, i) => { if (faint.test(code(line))) hits.push(`${rel(p)}:${i + 1}`); });
    }
    expect(hits).toEqual([]);
  });
});

describe("type", () => {
  test("strings use a real ellipsis", () => {
    const hits = [];
    for (const p of qml)
      read(p).split("\n").forEach((line, i) => {
        if (/"[^"]*\w\.\.\.(\s|"|\))/.test(code(line))) hits.push(`${rel(p)}:${i + 1}`);
      });
    expect(hits).toEqual([]);
  });
});
