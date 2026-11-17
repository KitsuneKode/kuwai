// The clipboard panel's overlay modes and undo for delete.
// `bun test tests/shell/clipstate.test.mjs`
import { describe, expect, test } from "bun:test";
import {
  MODES, OVERLAYS, parentOf, toggle, leave, surfaces, overlayCount, holdsOpen, route, escapeStep,
  empty, hold, held, visible, withoutPins, withPins, canUndo, undo, commit, prune, toState, fromState, keysOf,
} from "../../shell/services/clipstate.mjs";

const UNDO = 5000;
const item = (id, extra = {}) => ({ id, pin: "", secret: false, ...extra });
const pin = (file) => ({ id: "", pin: file, secret: false, source: "" });
const history = ["9", "8", "7", "6", "5"].map((id) => item(id));
const ids = (list) => list.map((e) => e.id);

describe("modes: one overlay at most", () => {
  test("every mode shows at most one overlay", () => {
    for (const m of MODES) expect(overlayCount(m)).toBeLessThanOrEqual(1);
    expect(overlayCount("browse")).toBe(0);
  });

  test("every overlay has a mode, and only that mode shows it", () => {
    for (const o of OVERLAYS) {
      const showing = MODES.filter((m) => surfaces(m)[o]);
      // Quick Look shows while browsing it and while editing in it.
      expect(showing.length).toBe(o === "quickLook" ? 2 : 1);
    }
  });

  test("entering any mode from any other leaves the first", () => {
    for (const a of MODES)
      for (const b of MODES) {
        if (a === b) continue;
        const now = toggle(a, b);
        expect(now).toBe(b);
        for (const o of OVERLAYS) if (surfaces(a)[o] && !surfaces(b)[o]) expect(surfaces(now)[o]).toBe(false);
        expect(overlayCount(now)).toBeLessThanOrEqual(1);
      }
  });

  test("every pair of overlay chords stays exclusive whatever order they come in", () => {
    const chords = ["help", "question", "actions", "date", "look", "read", "wipe", "escape", "other"];
    for (const start of MODES)
      for (const c1 of chords)
        for (const c2 of chords) {
          let m = start;
          for (const c of [c1, c2]) {
            const r = route(m, c);
            if (r.mode) m = r.mode;
            expect(overlayCount(m)).toBeLessThanOrEqual(1);
          }
        }
  });

  test("the bugs that started this: ⌃D over the menu, F1 over Quick Look and naming, ⌃K over Quick Look", () => {
    expect(route("actions", "date")).toEqual({ mode: "date", next: "done" });
    expect(surfaces("date").actionMenu).toBe(false);
    expect(route("quicklook", "help")).toEqual({ mode: "keys", next: "done" });
    expect(surfaces("keys").quickLook).toBe(false);
    // Naming owns its keys: F1 there opens nothing.
    expect(route("naming", "help")).toEqual({ next: "ignore" });
    expect(route("edit", "help")).toEqual({ next: "ignore" });
    expect(route("edit", "actions")).toEqual({ next: "ignore" });
    expect(route("quicklook", "actions")).toEqual({ mode: "actions", next: "done" });
    expect(surfaces("actions").quickLook).toBe(false);
  });

  test("the same key closes what it opened", () => {
    expect(route("actions", "actions")).toEqual({ mode: "browse", next: "done" });
    expect(route("date", "date")).toEqual({ mode: "browse", next: "done" });
    expect(toggle("quicklook", "quicklook")).toBe("browse");
    expect(toggle("edit", "edit")).toBe("quicklook");
  });

  test("the key sheet: any key closes it and does nothing else", () => {
    for (const c of ["escape", "help", "actions", "date", "look", "other", "wipe"])
      expect(route("keys", c)).toEqual({ mode: "browse", next: "done" });
    expect(route("keys", "modifier")).toEqual({ next: "ignore" });
  });

  test("in a menu, ? and Space are letters of its filter; the calendar gets its keys", () => {
    expect(route("actions", "question")).toEqual({ next: "overlay" });
    expect(route("filter", "look")).toEqual({ next: "overlay" });
    expect(route("date", "look")).toEqual({ next: "overlay" });
    expect(route("date", "other")).toEqual({ next: "overlay" });
    expect(route("browse", "question")).toEqual({ mode: "keys", next: "done" });
  });

  test("asking to clear history: a second ⌃⇧⌫ goes to the shelf, anything else calls it off", () => {
    expect(route("confirmWipe", "wipe")).toEqual({ next: "shelf" });
    expect(route("confirmWipe", "other")).toEqual({ mode: "browse", next: "shelf" });
    expect(route("confirmWipe", "escape")).toEqual({ mode: "browse", next: "done" });
    // Pressing ⌃ and ⇧ on the way to the second ⌫ doesn't call it off.
    expect(route("confirmWipe", "modifier")).toEqual({ next: "ignore" });
  });

  test("a surface closing itself backs up only if it was the one showing", () => {
    expect(leave("actions", "actions")).toBe("browse");
    expect(leave("date", "actions")).toBe("date");
    expect(leave("edit", "quicklook")).toBe("edit");
    expect(leave("edit", "edit")).toBe("quicklook");
  });

  test("unknown modes are treated as browse", () => {
    expect(parentOf("nonsense")).toBe("browse");
    expect(toggle("nonsense", "keys")).toBe("keys");
    expect(toggle("browse", "nonsense")).toBe("browse");
  });

  test("the idle timer waits while you're in the middle of something", () => {
    expect(MODES.filter(holdsOpen).sort()).toEqual(["actions", "date", "edit", "keys", "naming"]);
  });
});

describe("Esc steps back one level", () => {
  test("the tree: edit → quicklook → browse; every other overlay → browse", () => {
    expect(route("edit", "escape")).toEqual({ mode: "quicklook", next: "done" });
    expect(route("quicklook", "escape")).toEqual({ mode: "browse", next: "done" });
    for (const m of ["naming", "actions", "filter", "date", "keys", "confirmWipe"])
      expect(route(m, "escape")).toEqual({ mode: "browse", next: "done" });
    expect(route("browse", "escape")).toEqual({ next: "shelf" });
  });

  test("from anywhere, Esc reaches browse in at most two presses", () => {
    for (const m of MODES) {
      let cur = m, n = 0;
      while (cur !== "browse") { cur = route(cur, "escape").mode; n++; }
      expect(n).toBeLessThanOrEqual(2);
    }
  });

  test("in browse: marks, then the search, then the type filter, then the date, then close", () => {
    let s = { marks: 2, query: "npm", filter: "code", date: true };
    const order = [];
    for (;;) {
      const step = escapeStep(s);
      order.push(step);
      if (step === "close") break;
      if (step === "marks") s = { ...s, marks: 0 };
      if (step === "query") s = { ...s, query: "" };
      if (step === "filter") s = { ...s, filter: "all" };
      if (step === "date") s = { ...s, date: false };
    }
    expect(order).toEqual(["marks", "query", "filter", "date", "close"]);
  });
});

describe("undo for delete", () => {
  test("delete hides the entry; undo brings it back in its place", () => {
    let h = hold(empty(), [history[2]], [], 1000, UNDO);
    expect(ids(visible(history, h))).toEqual(["9", "8", "6", "5"]);
    expect(canUndo(h, 1000 + UNDO - 1)).toBe(true);
    const r = undo(h, 2000);
    expect(r.batch.ids).toEqual(["7"]);
    expect(ids(visible(history, r.holds))).toEqual(["9", "8", "7", "6", "5"]);
    expect(keysOf(r.batch)).toEqual(["i:7"]);
  });

  test("a new list from cliphist mid-window still hides it", () => {
    const h = hold(empty(), [history[0]], [], 0, UNDO);
    const fresh = [item("10"), ...history];          // something new was copied meanwhile
    expect(ids(visible(fresh, h))).toEqual(["10", "8", "7", "6", "5"]);
  });

  test("a multi-selection is one delete and one undo", () => {
    const h = hold(empty(), [history[1], history[3], history[4]], [], 0, UNDO);
    expect(ids(visible(history, h))).toEqual(["9", "7"]);
    const r = undo(h, 10);
    expect(r.batch.ids).toEqual(["8", "6", "5"]);
    expect(ids(visible(history, r.holds))).toEqual(ids(history));
    expect(canUndo(r.holds, 10)).toBe(false);
  });

  test("two deletes, two undos, newest first", () => {
    let h = hold(empty(), [history[0]], [], 0, UNDO);
    h = hold(h, [history[4]], [], 100, UNDO);
    let r = undo(h, 200);
    expect(r.batch.ids).toEqual(["5"]);
    expect(ids(visible(history, r.holds))).toEqual(["8", "7", "6", "5"]);
    r = undo(r.holds, 300);
    expect(r.batch.ids).toEqual(["9"]);
    expect(ids(visible(history, r.holds))).toEqual(ids(history));
  });

  test("a later delete extends the window for what's still held", () => {
    let h = hold(empty(), [history[0]], [], 0, UNDO);
    h = hold(h, [history[1]], [], 4000, UNDO);
    expect(canUndo(h, 8000)).toBe(true);
    expect(canUndo(h, 9000)).toBe(false);
  });

  test("a pin comes back to its place in the pin list", () => {
    const pins = [pin("c.txt"), pin("b.txt"), pin("a.txt")];
    const h = hold(empty(), [pins[1]], pins, 0, UNDO);
    const batch = h.batches[0];
    const shown = withoutPins(pins, batch);
    expect(shown.map((p) => p.pin)).toEqual(["c.txt", "a.txt"]);
    const r = undo(h, 1);
    expect(withPins(shown, r.batch).map((p) => p.pin)).toEqual(["c.txt", "b.txt", "a.txt"]);
    expect(keysOf(r.batch)).toEqual(["p:b.txt"]);
  });

  test("several pins and copies in one delete all come back where they were", () => {
    const pins = [pin("d"), pin("c"), pin("b"), pin("a")];
    const h = hold(empty(), [pins[0], history[2], pins[2], pins[3]], pins, 0, UNDO);
    const shown = withoutPins(pins, h.batches[0]);
    expect(shown.map((p) => p.pin)).toEqual(["c"]);
    const r = undo(h, 1);
    expect(withPins(shown, r.batch).map((p) => p.pin)).toEqual(["d", "c", "b", "a"]);
    expect(ids(visible(history, r.holds))).toEqual(ids(history));
  });

  test("undo after the window is a no-op", () => {
    const h = hold(empty(), [history[0]], [], 0, UNDO);
    const r = undo(h, UNDO);
    expect(r.batch).toBe(null);
    expect(r.holds).toBe(h);
    expect(ids(visible(history, r.holds))).toEqual(["8", "7", "6", "5"]);
    expect(undo(empty(), 0).batch).toBe(null);
  });

  test("undo after the window ended (committed) is a no-op too", () => {
    const c = commit(hold(empty(), [history[0]], [], 0, UNDO));
    const r = undo(c.holds, 1);
    expect(r.batch).toBe(null);
    expect(ids(visible(history, r.holds))).toEqual(["8", "7", "6", "5"]);
  });

  test("when the window ends, everything held is deleted for real, secrets included", () => {
    const secret = item("4", { secret: true });
    const list = [...history, secret];
    let h = hold(empty(), [secret, history[0]], [pin("x")], 0, UNDO);
    h = hold(h, [pin("x")], [pin("x")], 10, UNDO);
    const c = commit(h);
    expect(c.ids.sort()).toEqual(["4", "9"]);
    expect(c.secrets).toEqual(["4"]);
    expect(c.pins).toEqual(["x"]);
    expect(c.holds.batches).toEqual([]);
    expect(canUndo(c.holds, 11)).toBe(false);
    // Hidden until cliphist's list no longer has them, then forgotten.
    expect(ids(visible(list, c.holds))).toEqual(["8", "7", "6", "5"]);
    const after = prune(c.holds, history.slice(1));
    expect(held(after)).toEqual({});
  });

  test("a restart mid-window purges what was held instead of showing it", () => {
    const secret = item("4", { secret: true });
    const pins = [pin("p1")];
    const h = hold(empty(), [secret, pins[0]], pins, 0, UNDO);
    const saved = JSON.parse(JSON.stringify({ held: toState(h) }));
    expect(fromState(saved.held)).toEqual({ ids: ["4"], pins: ["p1"] });
    expect(fromState(undefined)).toEqual({ ids: [], pins: [] });
    expect(fromState({ ids: "4", pins: [3, "", "ok"] })).toEqual({ ids: [], pins: ["ok"] });
  });

  test("deleting nothing, or the same entry twice, holds nothing new", () => {
    const h0 = empty();
    expect(hold(h0, [], [], 0, UNDO)).toBe(h0);
    const h1 = hold(h0, [history[0]], [], 0, UNDO);
    expect(hold(h1, [history[0]], [], 1, UNDO)).toBe(h1);
    expect(hold(h0, [pin("missing")], [pin("other")], 0, UNDO)).toBe(h0);
  });

  test("nothing held: the list is passed through untouched", () => {
    expect(visible(history, empty())).toBe(history);
  });
});
