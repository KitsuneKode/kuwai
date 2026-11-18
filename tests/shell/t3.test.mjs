// What a T3 thread's row says, and the reply preview. `bun test tests/shell/t3.test.mjs`
import { describe, expect, test } from "bun:test";
import { stateOf, spoken, since, excerpt } from "../../shell/services/t3.mjs";

describe("the row names the state", () => {
  test("why it needs you: three different things", () => {
    expect(stateOf({ status: "waiting", ask: "approval" }).word).toBe("Approval");
    expect(stateOf({ status: "waiting", ask: "question" }).word).toBe("Question");
    expect(stateOf({ status: "waiting", ask: "request" }).word).toBe("Request");
    expect(stateOf({ status: "waiting" }).word).toBe("Needs you");              // an older helper: still true
    for (const ask of ["approval", "question", "request", undefined]) expect(stateOf({ status: "waiting", ask }).tone).toBe("attention");
  });
  test("parked on another thread is not working", () => {
    expect(stateOf({ status: "running", blocked: true })).toEqual({ key: "blocked", word: "Waiting", tone: "idle", timed: false });
    expect(stateOf({ status: "running" }).word).toBe("Working");
  });
  test("stopped by a limit is not a failure of the work", () => {
    expect(stateOf({ status: "failed", limited: true })).toMatchObject({ word: "Limit reached", tone: "caution" });
    expect(stateOf({ status: "failed" })).toMatchObject({ word: "Failed", tone: "error" });
  });
  test("done, starting, and nothing known", () => {
    expect(stateOf({ status: "completed" })).toMatchObject({ word: "Done", tone: "done", timed: true });
    expect(stateOf({ status: "preparing" }).word).toBe("Starting");
    expect(stateOf(null).word).toBe("Starting");
  });
  test("a thread that wants you is not timed; work and its end are", () => {
    expect(stateOf({ status: "waiting", ask: "approval" }).timed).toBe(false);
    expect(stateOf({ status: "running" }).timed).toBe(true);
  });
  test("every state has words for a screen reader", () => {
    for (const t of [{ status: "waiting", ask: "approval" }, { status: "waiting", ask: "question" }, { status: "waiting", ask: "request" }, { status: "waiting" },
                     { status: "running" }, { status: "running", blocked: true }, { status: "failed" }, { status: "failed", limited: true }, { status: "completed" }, {}])
      expect(spoken(t).length).toBeGreaterThan(4);
    expect(spoken({ status: "running", blocked: true })).toBe("Waiting on another thread");
  });
});

describe("how long", () => {
  const now = Date.parse("2026-11-19T12:00:00Z");
  test("short, in the largest unit", () => {
    expect(since("2026-11-19T11:59:40Z", now)).toBe("now");
    expect(since("2026-11-19T11:52:00Z", now)).toBe("8m");
    expect(since("2026-11-19T09:10:00Z", now)).toBe("2h");
    expect(since("2026-11-16T12:00:00Z", now)).toBe("3d");
    expect(since(now - 5 * 60000, now)).toBe("5m");
  });
  test("a time that can't be read says nothing", () => {
    expect(since("", now)).toBe("");
    expect(since(undefined, now)).toBe("");
    expect(since("@now-1700iso", now)).toBe("");
  });
  test("a clock a little ahead is now, not negative", () => expect(since("2026-11-19T12:00:30Z", now)).toBe("now"));
});

describe("the reply preview", () => {
  test("plain lines: no code, no marks, links as their labels", () => {
    const md = "## Done\n\nThe **implementation** is ready, see [the PR](https://example.com/pr/1).\n\n```sh\nmake test\n```\n\n- keyboard `navigation`\n* tray actions\n> a note";
    expect(excerpt(md)).toBe("Done\nThe implementation is ready, see the PR.\n• keyboard navigation\n• tray actions\na note");
  });
  test("five lines at most, then an ellipsis", () => {
    const out = excerpt(["one", "two", "three", "four", "five", "six"].join("\n\n"));
    expect(out.split("\n").length).toBe(5);
    expect(out.endsWith("five…")).toBe(true);
  });
  test("360 characters at most, cut at a word", () => {
    const out = excerpt("word ".repeat(200));
    expect(Array.from(out).length).toBeLessThanOrEqual(361);
    expect(out.endsWith("word…")).toBe(true);
  });
  test("an unclosed code block does not leak its contents", () => expect(excerpt("Running:\n```sh\nrm -rf build")).toBe("Running:"));
  test("nothing in, nothing out", () => {
    expect(excerpt("")).toBe("");
    expect(excerpt(null)).toBe("");
    expect(excerpt("```\nonly code\n```")).toBe("");
  });
  test("rules between sections are not lines", () => expect(excerpt("a\n\n---\n\nb")).toBe("a\nb"));
});
