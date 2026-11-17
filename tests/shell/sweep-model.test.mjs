// What the island says about idle projects (shell/services/sweepModel.js).
//   bun test tests/shell/sweep-model.test.mjs
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const lib = readFileSync(new URL("../../shell/services/sweepModel.js", import.meta.url), "utf8").replace(/^\.pragma library\s*$/m, "");
const names = ["compact", "long", "segments", "worthMark", "parseViewed", "viewedText", "isFresh", "reconcileViewed", "viewedAfterLook",
    "headline", "caption", "tilde", "emptyText", "footText", "idleText", "agoText"];
const { headline, caption, compact, long, segments, worthMark, parseViewed, viewedText, isFresh, reconcileViewed, viewedAfterLook, tilde, emptyText, footText, idleText, agoText } =
    new Function(lib + "\nreturn { " + names.join(", ") + " };")();
const GB = 1e9;

describe("sizes", () => {
    test("the mark's value is short", () => {
        expect(compact(16.2 * GB)).toBe("16G");
        expect(compact(9.54 * GB)).toBe("9.5G");
        expect(compact(640e6)).toBe("640M");
        expect(compact(0)).toBe("1M");
        expect(compact(undefined)).toBe("1M");
    });
    test("the header's line", () => {
        expect(headline(16.24 * GB, 38, 30)).toBe("16.2 GB · 38 projects idle 30+ days");
        expect(headline(12 * GB, 1, 30)).toBe("12 GB · 1 project idle 30+ days");
    });
    test("the panel has room for the unit", () => {
        expect(long(16.24 * GB)).toBe("16.2 GB");
        expect(long(123.4 * GB)).toBe("123 GB");
        expect(long(40e6)).toBe("40 MB");
    });
});

describe("the bar", () => {
    const tones = ["a", "b", "c", "d", "e"];
    const kinds = [{ kind: "target", bytes: 20, count: 2 }, { kind: "node_modules", bytes: 60, count: 9 }, { kind: ".next", bytes: 15, count: 1 }, { kind: ".turbo", bytes: 3, count: 1 }, { kind: "dist", bytes: 2, count: 1 }];
    test("biggest first, small ones fold into other, shares add to one", () => {
        const s = segments(kinds, 100, tones);
        expect(s.map(x => x.kind)).toEqual(["node_modules", "target", ".next", "other"]);
        expect(s.reduce((a, x) => a + x.share, 0)).toBeCloseTo(1, 9);
        expect(s[3].bytes).toBe(5);
        expect(s.map(x => x.tone)).toEqual(["a", "b", "c", "d"]);
    });
    test("at most `max` named parts", () => {
        const many = Array.from({ length: 8 }, (_, i) => ({ kind: "k" + i, bytes: 12, count: 1 }));
        const s = segments(many, 96, tones, 3);
        expect(s.length).toBe(4);
        expect(s[3].kind).toBe("other");
    });
    test("the bar from the idle kinds adds up to the headline; the fallback says it's everything", () => {
        const idle = [{ kind: "node_modules", bytes: 5 * GB, count: 2 }, { kind: "target", bytes: 2 * GB, count: 1 }];
        const s = segments(idle, 7 * GB, tones);
        expect(s.reduce((a, x) => a + x.bytes, 0)).toBe(7 * GB);
        expect(caption(null, true, 56 * GB)).toBe("What the idle projects hold · rest on a part");
        expect(caption(s[0], true, 56 * GB)).toBe("node_modules · 5 GB · 2 folders");
        expect(caption(null, false, 56 * GB)).toBe("All projects, idle or not: 56 GB · rest on a part");
        expect(caption({ kind: "other", bytes: GB, count: 0 }, false, 56 * GB)).toBe("Everything else · 1 GB · all projects");
    });
    test("nothing to show is no bar", () => {
        expect(segments([], 0, tones)).toEqual([]);
        expect(segments(null, 100, tones)).toEqual([]);
        expect(segments([{ kind: "x", bytes: 0 }], 100, tones)).toEqual([]);
    });
});

describe("worth a mark", () => {
    test("only past the threshold", () => {
        expect(worthMark(9 * GB, 10 * GB)).toBe(false);
        expect(worthMark(10 * GB, 10 * GB)).toBe(true);
        expect(worthMark(0, 0)).toBe(false);
    });
});

describe("looked at", () => {
    const MIN = 10 * GB;
    // What the shell does: a count arrives (reconcile), you look (viewedAfterLook).
    const look = (idle, v) => viewedAfterLook(idle, v, MIN);
    const count = (idle, v) => reconcileViewed(idle, v, MIN);
    test("unseen and worth it: the mark shows", () => {
        expect(isFresh(12 * GB, null, MIN)).toBe(true);
        expect(isFresh(9 * GB, null, MIN)).toBe(false);
    });
    test("14.9 GB looked at, then 15.0 GB: still seen (no 5 GB step boundary)", () => {
        const v = look(14.9 * GB, null);
        expect(v).toBe(14.9 * GB);
        expect(isFresh(15.0 * GB, count(15.0 * GB, v), MIN)).toBe(false);
    });
    test("16 GB looked at, cleaned down to 12 GB: stays quiet", () => {
        const v = count(12 * GB, look(16 * GB, null));
        expect(v).toBe(12 * GB);                 // follows the number down
        expect(isFresh(12 * GB, v, MIN)).toBe(false);
    });
    test("5 GB of growth past what you saw brings it back", () => {
        const v = look(16 * GB, null);
        expect(isFresh(20.9 * GB, count(20.9 * GB, v), MIN)).toBe(false);
        expect(isFresh(21 * GB, count(21 * GB, v), MIN)).toBe(true);
        // …and after a clean-up, 5 GB past what is left.
        const after = count(12 * GB, v);
        expect(isFresh(17 * GB, count(17 * GB, after), MIN)).toBe(true);
    });
    test("dropping under the threshold forgets the look", () => {
        expect(count(9 * GB, 16 * GB)).toBe(null);
        expect(isFresh(10 * GB, count(10 * GB, null), MIN)).toBe(true);
    });
    test("looking again keeps the larger size; under the threshold keeps nothing new", () => {
        expect(look(19 * GB, 16 * GB)).toBe(19 * GB);
        expect(look(8 * GB, null)).toBe(null);
    });
    test("the file: bytes now, the old step key still read, junk is unseen", () => {
        expect(parseViewed(viewedText(16.2 * GB))).toBe(16.2 * GB);
        expect(viewedText(null)).toBe("");
        expect(parseViewed("3\n")).toBe(15 * GB);              // old: looked at in 15–20 GB
        expect(isFresh(19.9 * GB, parseViewed("3"), MIN)).toBe(false);
        expect(isFresh(20 * GB, parseViewed("3"), MIN)).toBe(true);   // where the old key came back
        for (const junk of ["", "  ", "nope", "{}", '{"bytes":"x"}', '{"bytes":-1}', "[]", "null", undefined, null])
            expect(parseViewed(junk)).toBe(null);
    });
});

describe("states", () => {
    const now = 1_800_000_000_000;
    const base = { loaded: true, alive: true, pending: false, error: "", counted: true, root: "/home/me/Projects", home: "/home/me", hasBar: true };
    test("a path under home is shown with ~", () => {
        expect(tilde("/home/me/Projects", "/home/me")).toBe("~/Projects");
        expect(tilde("/home/meow/x", "/home/me")).toBe("/home/meow/x");
        expect(tilde("/srv/x", "")).toBe("/srv/x");
    });
    test("a failed first count says what failed, not Counting… forever", () => {
        expect(emptyText({ ...base, counted: false, error: "folder missing", hasBar: false })).toBe("Couldn't count ~/Projects: folder missing.");
        expect(emptyText({ ...base, counted: false, pending: true, hasBar: false })).toBe("Counting ~/Projects…  the first scan can take a minute.");
        expect(emptyText({ ...base, loaded: false })).toBe("Looking for sweep…");
        expect(emptyText({ ...base, alive: false })).toBe("sweep isn't installed — bun add -g @kitsunekode/sweep @opentui/core");
        expect(emptyText({ ...base, hasBar: false })).toBe("Nothing to free here.");
        expect(emptyText(base)).toBe("");
    });
    test("the footer: when, and what the count is doing now", () => {
        const s = { protectedCount: 2, checkedAt: now / 1000 - 3 * 3600, pending: false, refreshing: false, error: "", counted: true };
        expect(footText(s, now)).toBe("2 protected · counted 3 h ago");
        expect(footText({ ...s, refreshing: true }, now)).toBe("2 protected · counted 3 h ago · counting again…");
        expect(footText({ ...s, error: "scan failed (exit 3)" }, now)).toBe("2 protected · counted 3 h ago · couldn't count again: scan failed (exit 3)");
        expect(footText({ ...s, protectedCount: 0, checkedAt: 0, counted: false, pending: true, refreshing: true }, now)).toBe("");
    });
});

describe("words", () => {
    test("idle time", () => {
        expect(idleText(34)).toBe("34 days");
        expect(idleText(212)).toBe("7 months");
        expect(idleText(400)).toBe("1 year");
        expect(idleText(800)).toBe("2 years");
    });
    test("when it was last counted", () => {
        const now = 1_800_000_000_000;
        expect(agoText(now / 1000 - 20, now)).toBe("just now");
        expect(agoText(now / 1000 - 12 * 60, now)).toBe("12 min ago");
        expect(agoText(now / 1000 - 3 * 3600, now)).toBe("3 h ago");
        expect(agoText(now / 1000 - 3 * 86400, now)).toBe("3 d ago");
    });
    test("nothing counted yet says nothing, not decades ago", () => {
        const now = 1_800_000_000_000;
        expect(agoText(0, now)).toBe("");
        expect(agoText(undefined, now)).toBe("");
        expect(agoText(null, now)).toBe("");
    });
});
