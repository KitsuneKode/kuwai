// Moments' memory of announced calendar events is bounded: an event an hour
// past its start is forgotten. `bun test tests/shell/moments.test.mjs`
import { describe, expect, test } from "bun:test";
import { forgetAnnounced } from "../../shell/services/moments.mjs";

const H = 3600000;

describe("forgetAnnounced", () => {
  test("keeps what's still current and forgets what started over an hour ago", () => {
    const now = 1_800_000_000_000;
    const a = { [`${now - 2 * H}|Old|10`]: true, [`${now - 2 * H}|Old|0`]: true, [`${now - 10 * 60000}|Standup|0`]: true, [`${now + H}|Later|10`]: true };
    expect(forgetAnnounced(a, now)).toEqual({ [`${now - 10 * 60000}|Standup|0`]: true, [`${now + H}|Later|10`]: true });
  });
  test("nothing to forget: the same object back (no change to notify)", () => {
    const a = { "1800000000000|X|10": true };
    expect(forgetAnnounced(a, 1_800_000_000_000)).toBe(a);
  });
  test("a day of events stays a handful of keys", () => {
    let a = {};
    const start = 1_800_000_000_000;
    for (let i = 0; i < 1000; i++) {
      const t = start + i * 30 * 60000;           // an event every half hour, for 20 days
      a = forgetAnnounced(a, t);
      a = { ...a, [`${t}|E${i}|10`]: true, [`${t}|E${i}|0`]: true };
    }
    expect(Object.keys(a).length).toBeLessThanOrEqual(6);
  });
});
