import { describe, expect, test } from "bun:test";
import { headline, target, merge, until, t3Agent } from "../../shell/services/agents.mjs";

const now = Date.parse("2026-11-22T12:00:00Z");
const pane = (o) => Object.assign({ key: "p", agent: "claude", state: "working", working: true, since: 0 }, o);
const thread = (o) => Object.assign({ thread: "t", provider: "codex", status: "running", at: "2026-11-22T11:00:00Z" }, o);

describe("one capsule says the one thing that matters most", () => {
  test("nothing going on: nothing to say", () => {
    expect(headline([], [], 0, 0, now)).toMatchObject({ word: "", tone: "", working: 0, done: 0 });
  });
  test("only working: no word, the count of both kinds", () => {
    const h = headline([pane({})], [thread({})], 0, 0, now);
    expect(h).toMatchObject({ word: "", tone: "working", working: 2 });
  });
  test("an approval in T3 outranks kitty agents working", () => {
    const h = headline([pane({}), pane({ key: "q" })], [thread({ status: "waiting", ask: "approval" })], 0, 0, now);
    expect(h).toMatchObject({ word: "Approval", tone: "attention", count: 1, working: 2 });
  });
  test("two approvals, one from each, say Approval 2", () => {
    const h = headline([pane({ state: "waiting", needs: true, working: false, ask: true })], [thread({ status: "waiting", ask: "approval" })], 0, 0, now);
    expect(h.word).toBe("Approval 2");
  });
  test("different asks say Needs you with the count", () => {
    const h = headline([pane({ state: "waiting", needs: true, working: false })], [thread({ status: "waiting", ask: "question" })], 0, 0, now);
    expect(h.word).toBe("Needs you 2");
  });
  test("a failure outranks a limit", () => {
    const h = headline([pane({ state: "limited", working: false, limitReset: now / 1000 + 2460 })], [thread({ status: "failed" })], 0, 0, now);
    expect(h).toMatchObject({ word: "Failed", tone: "error" });
  });
  test("a limit says when it's back, the soonest of them", () => {
    const h = headline([pane({ state: "limited", working: false, limitReset: now / 1000 + 7500 }), pane({ key: "b", state: "limited", working: false, limitReset: now / 1000 + 2460 })], [], 0, 0, now);
    expect(h).toMatchObject({ word: "Back in 41m", tone: "caution", count: 2 });
  });
  test("a limit with no known reset says so", () => {
    expect(headline([], [thread({ status: "failed", limited: true })], 0, 0, now).word).toBe("Limit reached");
  });
  test("finished and unseen counts both kinds", () => {
    expect(headline([], [], 2, 3, now)).toMatchObject({ tone: "done", done: 5 });
  });
});

describe("go to what needs me", () => {
  test("the one that has waited longest", () => {
    const t = target([pane({ key: "late", state: "waiting", needs: true, working: false, since: now / 1000 - 60 })],
      [thread({ thread: "early", status: "waiting", ask: "approval", at: "2026-11-22T11:00:00Z" })]);
    expect(t).toMatchObject({ src: "t3", thread: "early" });
  });
  test("a kitty pane carries its event and action", () => {
    const t = target([pane({ state: "waiting", needs: true, working: false, event: "e1", action: { w: 3 } })], []);
    expect(t).toMatchObject({ src: "kitty", event: "e1", action: { w: 3 } });
  });
  test("working agents are never the answer", () => {
    expect(target([pane({})], [thread({})])).toBeNull();
  });
  test("a failure is, when nothing asks", () => {
    expect(target([pane({ state: "error", working: false })], [])).toMatchObject({ src: "kitty", word: "Failed" });
  });
  test("idle and done ones are left out of the merged list", () => {
    expect(merge([pane({ state: "idle", working: false })], [thread({ status: "completed" })])).toEqual([]);
  });
});

describe("small readings", () => {
  test("until", () => {
    expect(until(now + 125 * 60000, now)).toBe("2h 5m");
    expect(until(now + 60 * 60000, now)).toBe("1h");
    expect(until(now - 1, now)).toBe("");
  });
  test("T3 providers as kittymux's marks", () => {
    expect(t3Agent("claudeAgent")).toBe("claude");
    expect(t3Agent("codex_2")).toBe("codex");
    expect(t3Agent("newthing")).toBe("newthing");
  });
});
