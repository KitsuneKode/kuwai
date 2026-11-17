// The Usage panel's forecast and freshness. `bun test tests/shell/usage.test.mjs`
import { describe, expect, test } from "bun:test";
import { elapsed, runsOut, span, freshness, sourceName } from "../../shell/services/usage.mjs";

const MIN = 60000, H = 60 * MIN, now = 1_800_000_000_000;
// A window `gone` into its `len`, with `used` % spent.
const win = (len, gone, used) => ({ used, durationMins: len / MIN, resetsAt: now + (len - gone) });

describe("runsOut: will it be spent before it resets?", () => {
  test("half the session used in the first fifth of it: out in 1 h, 3 h early", () => {
    const r = runsOut(win(5 * H, 1 * H, 50), now);
    expect(Math.round(r.inMs / MIN)).toBe(60);
    expect(Math.round(r.earlyMs / H)).toBe(3);
  });
  test("spending evenly, or slower, is no news", () => {
    expect(runsOut(win(5 * H, 2.5 * H, 50), now)).toBe(null);
    expect(runsOut(win(5 * H, 4 * H, 30), now)).toBe(null);
  });
  test("a little early is not worth a line (under 5 % of the window)", () => {
    // 52 % at the half-way mark: out about 12 min before a 5-hour reset.
    expect(runsOut(win(5 * H, 2.5 * H, 52), now)).toBe(null);
  });
  test("too soon to tell: the window just began, or nearly nothing is used", () => {
    expect(runsOut(win(5 * H, 5 * MIN, 20), now)).toBe(null);          // 5 minutes in
    expect(runsOut(win(7 * 24 * H, 6 * H, 9), now)).toBe(null);        // 3.6 % of a week
    expect(runsOut(win(7 * 24 * H, 2 * 24 * H, 4), now)).toBe(null);   // 4 % used
  });
  test("a week being spent twice as fast as it lasts", () => {
    const r = runsOut(win(7 * 24 * H, 2 * 24 * H, 60), now);
    expect(Math.round(r.inMs / H)).toBe(32);                           // 40 % left at 30 %/day
    expect(Math.round(r.earlyMs / H)).toBe(88);
  });
  test("spent already, or missing what a forecast needs", () => {
    expect(runsOut(win(5 * H, 1 * H, 100), now)).toBe(null);
    expect(runsOut({ used: 50 }, now)).toBe(null);
    expect(runsOut({ used: 50, resetsAt: now + H }, now)).toBe(null);
    expect(runsOut(null, now)).toBe(null);
  });
  test("elapsed is the share of the window gone", () => {
    expect(elapsed(win(5 * H, 1 * H, 0), now)).toBeCloseTo(0.2);
    expect(elapsed({ used: 1 }, now)).toBe(-1);
  });
});

describe("words", () => {
  test("span: the two largest units", () => {
    expect(span(42 * MIN)).toBe("42m");
    expect(span(3 * H + 5 * MIN)).toBe("3h 5m");
    expect(span(2 * 24 * H + 4 * H + 59 * MIN)).toBe("2d 4h");
    expect(span(-5)).toBe("0m");
  });
  test("freshness: say the age only when it matters", () => {
    expect(freshness(now - 20 * 1000, now, "t3")).toEqual({ known: true, stale: false, old: false, age: "just now" });
    expect(freshness(now - 12 * MIN, now, "t3")).toEqual({ known: true, stale: false, old: false, age: "12m ago" });
    expect(freshness(now - 45 * MIN, now, "t3")).toEqual({ known: true, stale: true, old: false, age: "45m ago" });
    expect(freshness(now - 4 * H, now, "t3")).toEqual({ known: true, stale: true, old: true, age: "4h 0m ago" });
    expect(freshness(now - 2 * MIN, now, "t3-cached").old).toBe(true);
    expect(freshness(0, now, "t3")).toEqual({ known: false, stale: false, old: false, age: "" });
  });
  test("sourceName", () => {
    expect(sourceName("t3")).toBe("T3 Code");
    expect(sourceName("kittymux")).toBe("kittymux");
    expect(sourceName("none")).toBe("");
  });
});
