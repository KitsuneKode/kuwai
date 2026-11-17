// The shell's caches that grow with use stay bounded (shell/services/caches.mjs):
// the clipboard's per-entry renders, and the assistant's rendered blocks.
// `bun test tests/shell/caches.test.mjs`
import { describe, expect, test } from "bun:test";
import * as Caches from "../../shell/services/caches.mjs";
import * as ClipState from "../../shell/services/clipstate.mjs";
import { functions } from "../helpers/qml.mjs";

describe("pruneKeyed", () => {
  test("drops refs that left the history, keeps the newest up to the cap", () => {
    const m = { a: 1, b: 2, c: 3, gone: 4 };
    expect(Caches.pruneKeyed(m, ["c", "b", "a"], 2)).toEqual({ c: 3, b: 2 });
  });
  test("nothing to drop: the same object back (no change to notify)", () => {
    const m = { a: 1, b: 2 };
    expect(Caches.pruneKeyed(m, ["a", "b", "x"], 5)).toBe(m);
  });
  test("numeric ids rank by place in the history, not by number", () => {
    const m = { "9": 1, "100": 2, "5000": 3 };
    expect(Object.keys(Caches.pruneKeyed(m, ["9", "5000", "100"], 2)).sort()).toEqual(["5000", "9"]);
  });
});

// Clipboard.qml's own functions (setRaw, render, liveRefs, pruneCaches), driven
// like cliphist would: copies arrive on top, the 750-entry cap pushes the
// oldest out, secrets expire, and the preview renders whatever is selected.
function clipboard() {
  const s = functions("shell/services/Clipboard.qml", ["setRaw", "render", "liveRefs", "pruneCaches", "ref"], {
    ClipState, Caches, raw: [], items: [], holds: ClipState.empty(), pins: [], renders: {}, thumbs: {}, pending: {}, fileInfo: {},
    renderCap: 100,
    capture(args, cb) { cb(JSON.stringify({ kind: "md", html: "<p>" + args[1] + "</p>".repeat(20) })); },
  });
  return s;
}

describe("Clipboard renders", () => {
  test("a render goes with its entry (deleted, expired, pushed past the cap)", () => {
    const s = clipboard();
    const e = id => ({ id: String(id), pin: "", preview: "x" + id, kind: "text" });
    s.setRaw([e(3), e(2), e(1)]);
    for (const x of s.raw) s.render(x, () => {});
    expect(Object.keys(s.renders).sort()).toEqual(["1", "2", "3"]);
    s.setRaw([e(3), e(1)]);                     // 2 deleted (or expired: both go through setRaw)
    expect(Object.keys(s.renders).sort()).toEqual(["1", "3"]);
  });
  test("pins keep their render; an unpinned one loses it", () => {
    const s = clipboard();
    s.pins = [{ pin: "p1.txt", source: "", preview: "pinned", kind: "text" }];
    s.setRaw([]);
    s.render({ id: "", pin: "p1.txt" }, () => {});
    expect(Object.keys(s.renders)).toEqual(["pin:p1.txt"]);
    s.pins = [];
    s.pruneCaches();
    expect(Object.keys(s.renders)).toEqual([]);
  });
  test("3,000 copies (four times the history) with the newest previewed each time: never more than the cap, never a gone entry", () => {
    const s = clipboard();
    let hist = [];
    let next = 1;
    let worst = 0;
    for (let i = 0; i < 3000; i++) {
      hist = [{ id: String(next++), pin: "", preview: "copy " + i, kind: "text" }].concat(hist).slice(0, 750);
      if (i % 7 === 0) hist = hist.filter((_, j) => j !== 3);      // a delete / an expired secret
      s.setRaw(hist);
      s.render(hist[0], () => {});
      if (i % 3 === 0 && hist[10]) s.render(hist[10], () => {});   // scrolling back
      s.thumbs[hist[0].id] = "file:///x"; s.pending[hist[0].id] = true;
      worst = Math.max(worst, Object.keys(s.renders).length);
    }
    const live = new Set(hist.map(e => e.id));
    expect(worst).toBeLessThanOrEqual(101);                          // the cap, plus the one just added before its prune
    expect(Object.keys(s.renders).every(k => live.has(k))).toBe(true);
    expect(Object.keys(s.thumbs).length).toBeLessThanOrEqual(750);
    expect(Object.keys(s.pending).length).toBeLessThanOrEqual(750);
  });
});

describe("the assistant's block HTML", () => {
  const md = (text, live) => ({ kind: "md", lang: "", text, live: !!live });

  test("a block's half-written versions go when a longer one arrives, and when it finishes", () => {
    const c = Caches.htmlCache();
    Caches.htmlPut(c, md("Hel", true), "<p>Hel</p>", 0);
    Caches.htmlPut(c, md("Hello wo", true), "<p>Hello wo</p>", 50);
    expect(c.map.size).toBe(1);
    Caches.htmlPut(c, md("Hello world"), "<p>Hello world</p>", 100);
    expect(c.map.size).toBe(1);
    expect(Caches.htmlGet(c, md("Hello world"))).toBe("<p>Hello world</p>");
    expect(Caches.htmlGet(c, md("Hello wo", true))).toBeUndefined();
  });
  test("an unrelated block's partial is left alone (no render loop between two)", () => {
    const c = Caches.htmlCache();
    Caches.htmlPut(c, md("Alpha", true), "a", 0);
    Caches.htmlPut(c, md("Beta", true), "b", 0);
    expect(c.map.size).toBe(2);
  });
  test("chars are counted exactly through puts, supersedes and evictions", () => {
    const c = Caches.htmlCache();
    for (let i = 0; i < 300; i++) Caches.htmlPut(c, md("block " + (i % 40) + " text".repeat(i % 9)), "h".repeat(i), i * 10000, { maxChars: 20000 });
    let sum = 0;
    for (const e of c.map.values()) sum += e.size;
    expect(c.chars).toBe(sum);
  });
  test("a long synthetic run: 2,000 streamed answers stay under the byte cap with no partials left", () => {
    const c = Caches.htmlCache();
    const maxChars = 400000;
    let now = 0, worst = 0, rendered = 0;
    for (let a = 0; a < 2000; a++) {
      const blocks = 3 + (a % 6);
      for (let b = 0; b < blocks; b++) {
        const full = ("Answer " + a + " block " + b + ": ").concat("lorem ipsum dolor sit amet ".repeat(4 + (a * 7 + b) % 30));
        for (let n = 8; n < full.length; n += 23) {               // the tail growing, 50 ms apart
          now += 50;
          Caches.htmlPut(c, md(full.slice(0, n), true), "<p>" + full.slice(0, n) + "</p>", now, { maxChars });
          rendered++;
        }
        now += 50;
        Caches.htmlPut(c, md(full), "<p>" + full + "</p>", now, { maxChars });
        worst = Math.max(worst, c.chars);
      }
    }
    expect(rendered).toBeGreaterThan(50000);
    expect(c.live.size).toBe(0);                                  // every partial superseded
    // Over the cap only by what the last few seconds rendered (never evicted while young).
    expect(worst).toBeLessThanOrEqual(maxChars + 60000);
    expect(c.map.size).toBeLessThanOrEqual(Caches.HTML_MAX_ENTRIES);
  });
  test("the default bound: ~4 MB of text and 1,500 blocks", () => {
    const c = Caches.htmlCache();
    let now = 0;
    for (let i = 0; i < 6000; i++) { now += 10000; Caches.htmlPut(c, md("b" + i + "x".repeat(3000)), "y".repeat(3000), now); }
    expect(c.chars).toBeLessThanOrEqual(Caches.HTML_MAX_CHARS);
    expect(c.map.size).toBeLessThanOrEqual(Caches.HTML_MAX_ENTRIES);
  });
  test("a just-rendered block is never evicted (the one on screen can't loop)", () => {
    const c = Caches.htmlCache();
    Caches.htmlPut(c, md("huge"), "z".repeat(5000), 0, { maxChars: 1000 });
    expect(Caches.htmlGet(c, md("huge"))).toBe("z".repeat(5000));
    Caches.htmlPut(c, md("next"), "q", 1000, { maxChars: 1000 });
    expect(Caches.htmlGet(c, md("huge"))).toBeDefined();          // younger than minAgeMs
    Caches.htmlPut(c, md("later"), "r", 10000, { maxChars: 1000 });
    expect(Caches.htmlGet(c, md("huge"))).toBeUndefined();
  });
});
