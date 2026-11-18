// Reaching for the hidden or minimal island, or passing by (shell/services/proximity.js).
//   bun test tests/shell/proximity.test.mjs
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const src = readFileSync(new URL("../../shell/services/proximity.js", import.meta.url), "utf8").replace(/^\.pragma library\s*$/m, "");
const { reaching, edgeSettled, foldDelay, inZone, crossing } = new Function(src + "\nreturn { reaching, edgeSettled, foldDelay, inZone, crossing };")();
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

describe("the reach is measured from the island at rest", () => {
  // A 200 px island on a 1920 px screen, its lower edge at 40: the zone is 156 px either side of the middle, to y 88.
  test("under it and just beside it: in", () => {
    expect(inZone(0, 60, 200, 40, 0)).toBe(true);
    expect(inZone(-150, 80, 200, 40, 0)).toBe(true);
  });
  test("past 56 px beside it, or 48 px below it: out", () => {
    expect(inZone(160, 60, 200, 40, 0)).toBe(false);
    expect(inZone(0, 92, 200, 40, 0)).toBe(false);
  });
  test("once near, 20 px of slack before it lets go", () => {
    expect(inZone(170, 60, 200, 40, 20)).toBe(true);
    expect(inZone(180, 60, 200, 40, 20)).toBe(false);
  });
  test("a pointer following a capsule outward leaves the zone: the zone does not follow", () => {
    // Nearing showed the details and the island grew to 420 px; the capsule beside it moved 110 px out.
    // The caller keeps passing the resting width (200), so a pointer at the capsule's new place is out.
    const rest = 200, capsuleNow = 420 / 2 + 8 + 30;
    expect(inZone(capsuleNow, 20, rest, 40, 20)).toBe(false);
    expect(inZone(capsuleNow, 20, 420, 40, 20)).toBe(true);       // what feeding it the grown width did
  });
});

describe("crossing the island on the way to a capsule", () => {
  test("sideways at a walking pace: crossing, the island waits", () => expect(crossing(600, 40)).toBe(true));
  test("either way", () => expect(crossing(-700, -100)).toBe(true));
  test("stopped on it: not crossing, it grows", () => expect(crossing(0, 0)).toBe(false));
  test("a slow drift: resting", () => expect(crossing(200, 0)).toBe(false));
  test("coming down onto it: reaching it", () => expect(crossing(300, 600)).toBe(false));
  test("diagonal, mostly down: reaching it", () => expect(crossing(500, 450)).toBe(false));
  test("nothing known: not crossing", () => expect(crossing()).toBe(false));
});
