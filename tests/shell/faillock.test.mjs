import { expect, test } from "bun:test";
import { DEFAULTS, parseConf, tally, missWords, lockedWords } from "../../shell/services/faillock.mjs";

const at = (s) => new Date(s).getTime();
const out = `kitsunekode:
When                Type  Source                                           Valid
2026-11-27 12:00:00 RHOST                                                  V
2026-11-27 12:01:00 RHOST                                                  V
2026-11-27 11:00:00 RHOST                                                  V
2026-11-27 12:02:00 RHOST                                                  I
`;

test("the system's faillock settings, or its defaults", () => {
    expect(parseConf("")).toEqual(DEFAULTS);
    expect(parseConf("# deny = 9\n deny = 5\nunlock_time = 0\n")).toEqual({ deny: 5, failInterval: 900, unlockTime: 0 });
});

test("only valid misses inside the interval count", () => {
    expect(tally(out, at("2026-11-27T12:05:00"), DEFAULTS)).toEqual({ fails: 2, lockedUntil: 0 });
});

test("reaching the limit locks until the last miss plus the wait", () => {
    const three = out + "2026-11-27 12:03:00 TTY  /dev/tty1  V\n";
    const t = tally(three, at("2026-11-27T12:05:00"), DEFAULTS);
    expect(t.fails).toBe(3);
    expect(t.lockedUntil).toBe(at("2026-11-27T12:13:00"));
    expect(tally(three, at("2026-11-27T12:05:00"), { ...DEFAULTS, unlockTime: 0 }).lockedUntil).toBe(0);
});

test("what a miss says", () => {
    expect(missWords(1, DEFAULTS)).toBe("Incorrect password · 2 tries left");
    expect(missWords(2, DEFAULTS)).toBe("Incorrect password · last try before a 10-minute wait");
    expect(missWords(3, DEFAULTS)).toBe("Incorrect password");
    expect(lockedWords(125)).toBe("Too many tries · try again in 2:05");
});
