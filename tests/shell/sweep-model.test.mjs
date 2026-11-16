// What the island says about idle projects (shell/services/sweepModel.js).
//   bun test tests/shell/sweep-model.test.mjs
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const lib = readFileSync(new URL("../../shell/services/sweepModel.js", import.meta.url), "utf8").replace(/^\.pragma library\s*$/m, "");
const { compact, long, segments, worthMark, seenKey, idleText, agoText } =
    new Function(lib + "\nreturn { compact, long, segments, worthMark, seenKey, idleText, agoText };")();
const GB = 1e9;

describe("sizes", () => {
    test("the mark's value is short", () => {
        expect(compact(16.2 * GB)).toBe("16G");
        expect(compact(9.54 * GB)).toBe("9.5G");
        expect(compact(640e6)).toBe("640M");
        expect(compact(0)).toBe("1M");
        expect(compact(undefined)).toBe("1M");
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
    test("seen until it grows by another 5 GB", () => {
        expect(seenKey(16.2 * GB)).toBe(seenKey(19.9 * GB));
        expect(seenKey(20 * GB)).not.toBe(seenKey(19.9 * GB));
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
});
