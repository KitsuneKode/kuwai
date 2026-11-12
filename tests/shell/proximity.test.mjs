// Reaching for the hidden or minimal island, or passing by (shell/services/proximity.js).
//   bun test tests/shell/proximity.test.mjs
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const src = readFileSync(new URL("../../shell/services/proximity.js", import.meta.url), "utf8").replace(/^\.pragma library\s*$/m, "");
const { reaching, edgeSettled, foldDelay } = new Function(src + "\nreturn { reaching, edgeSettled, foldDelay };")();
const p = (vx, vy, t = 0) => ({ vx, vy, speed: Math.hypot(vx, vy), t });

describe("in the zone below and beside it", () => {
  test("resting near it reaches", () => expect(reaching(p(40, -20))).toBe(true));
  test("a slow drift any way reaches", () => expect(reaching(p(300, 0))).toBe(true));
  test("heading up at it reaches", () => expect(reaching(p(200, -800))).toBe(true));
  test("heading up, but flying, passes by", () => expect(reaching(p(0, -1500))).toBe(false));
  test("sideways along the top passes by (to a tab)", () => expect(reaching(p(900, -100))).toBe(false));
  test("going down, away from it, passes by", () => expect(reaching(p(100, 700))).toBe(false));
  test("the old 2500 px/s cap let 2000 in; not now", () => expect(reaching(p(2000, 0))).toBe(false));
  test("nothing known reads as still", () => expect(reaching({})).toBe(true));
});

describe("on the edge strip", () => {
  test("moving fast along it: look again", () => expect(edgeSettled(p(1200, 0, 1000), 1080)).toBe(false));
  test("slowed down on it: open", () => expect(edgeSettled(p(200, 0, 1000), 1080)).toBe(true));
  test("an old sample says nothing: open", () => expect(edgeSettled(p(1200, 0, 1000), 1400)).toBe(true));
});

describe("leaving", () => {
  test("a fast exit folds at once", () => expect(foldDelay(p(0, 1500))).toBe(150));
  test("drifting away gets the grace", () => expect(foldDelay(p(0, 300))).toBe(450));
});
