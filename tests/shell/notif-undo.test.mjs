// Undo for clearing notifications: what is held, where it goes back, what is
// never written. `bun test tests/shell/notif-undo.test.mjs`
import { describe, expect, test } from "bun:test";
import { place, take, forget, restore, isHeld, persisted, label } from "../../shell/services/notifUndo.mjs";

const mk = (name, extra = {}) => Object.assign({ name }, extra);
const names = list => list.map(i => i.name);
const all = () => true;

describe("one clear, then Undo", () => {
  test("a row goes back where it stood", () => {
    const [a, b, c, d] = ["a", "b", "c", "d"].map(n => mk(n));
    const list = [a, b, c, d];
    const r = take(null, "center", list, [c], all);
    expect(r.end).toEqual([]);
    expect(names(r.batch.held)).toEqual(["c"]);
    expect(names(restore(r.batch, [a, b, d]))).toEqual(["a", "b", "c", "d"]);
  });

  test("an app's rows go back between the others", () => {
    const [a1, x, a2, y, a3] = ["a1", "x", "a2", "y", "a3"].map(n => mk(n));
    const list = [a1, x, a2, y, a3];
    const r = take(null, "center", list, [a1, a2, a3], all);
    expect(names(restore(r.batch, [x, y]))).toEqual(["a1", "x", "a2", "y", "a3"]);
  });

  test("clear all, undo: exactly as it was", () => {
    const list = ["a", "b", "c", "d", "e"].map(n => mk(n));
    const r = take(null, "center", list, list.slice(), all);
    expect(names(r.batch.held)).toEqual(["a", "b", "c", "d", "e"]);
    expect(restore(r.batch, [])).toEqual(list);
  });

  test("what arrived during the window stays on top", () => {
    const [a, b, c] = ["a", "b", "c"].map(n => mk(n));
    const r = take(null, "center", [a, b, c], [a, b, c], all);
    const n1 = mk("new1"), n2 = mk("new2");
    expect(names(restore(r.batch, [n2, n1]))).toEqual(["new2", "new1", "a", "b", "c"]);
  });

  test("the top row goes back above the rest, below newcomers", () => {
    const [a, b, c] = ["a", "b", "c"].map(n => mk(n));
    const r = take(null, "center", [a, b, c], [a], all);
    const n = mk("new");
    expect(names(restore(r.batch, [n, b, c]))).toEqual(["new", "a", "b", "c"]);
  });

  test("a neighbour that left meanwhile doesn't lose the place", () => {
    const [a, b, c, d] = ["a", "b", "c", "d"].map(n => mk(n));
    const r = take(null, "center", [a, b, c, d], [c], all);
    // b went (acted on) during the window: c goes after a, its nearest one left.
    expect(names(restore(r.batch, [a, d]))).toEqual(["a", "c", "d"]);
  });

  test("a toast still leaving is not doubled", () => {
    const [a, b, c] = ["a", "b", "c"].map(n => mk(n));
    const r = take(null, "center", [a, b, c], [b], all);
    // b is a popup: still in the list during its exit when Undo comes.
    expect(names(restore(r.batch, [a, b, c]))).toEqual(["a", "b", "c"]);
  });
});

describe("several clears in one window", () => {
  test("from the same surface they add up, and all go back in place", () => {
    const [a, b, c, d, e] = ["a", "b", "c", "d", "e"].map(n => mk(n));
    let r = take(null, "island", [a, b, c, d, e], [b], all);
    r = take(r.batch, "island", [a, c, d, e], [d], all);
    expect(r.end).toEqual([]);
    expect(names(r.batch.held)).toEqual(["b", "d"]);
    expect(label(r.batch)).toBe("Cleared 2 · Undo");
    expect(names(restore(r.batch, [a, c, e]))).toEqual(["a", "b", "c", "d", "e"]);
  });

  test("a clear from another surface ends the first batch", () => {
    const [a, b, c] = ["a", "b", "c"].map(n => mk(n));
    let r = take(null, "island", [a, b, c], [a], all);
    r = take(r.batch, "center", [b, c], [c], all);
    expect(names(r.end)).toEqual(["a"]);
    expect(r.batch.surface).toBe("center");
    expect(names(r.batch.held)).toEqual(["c"]);
    expect(names(restore(r.batch, [b]))).toEqual(["b", "c"]);
  });

  test("the same item cleared twice (a leaving toast, then Clear all) is held once", () => {
    const [a, b] = ["a", "b"].map(n => mk(n));
    let r = take(null, "center", [a, b], [a], all);
    r = take(r.batch, "center", [a, b], [a, b], all);
    expect(names(r.batch.held)).toEqual(["a", "b"]);
    expect(names(restore(r.batch, []))).toEqual(["a", "b"]);
  });
});

describe("never held", () => {
  const notCode = i => !i.code;
  test("a one-time code is ended at once, the rest held", () => {
    const [a, otp, b] = [mk("a"), mk("otp", { code: true }), mk("b")];
    const r = take(null, "center", [a, otp, b], [a, otp, b], notCode);
    expect(names(r.end)).toEqual(["otp"]);
    expect(names(r.batch.held)).toEqual(["a", "b"]);
    expect(label(r.batch)).toBe("Cleared 2 · Undo");
    // Undo never brings the code back.
    expect(names(restore(r.batch, []))).toEqual(["a", "b"]);
  });

  test("a clear of only codes offers no undo", () => {
    const otp = mk("otp", { code: true });
    const r = take(null, "island", [otp], [otp], notCode);
    expect(r.batch).toBeNull();
    expect(names(r.end)).toEqual(["otp"]);
    expect(label(r.batch)).toBe("");
  });

  test("a code cleared into an open batch doesn't end the batch", () => {
    const [a, otp] = [mk("a"), mk("otp", { code: true })];
    let r = take(null, "center", [a, otp], [a], notCode);
    r = take(r.batch, "center", [otp], [otp], notCode);
    expect(names(r.end)).toEqual(["otp"]);
    expect(names(r.batch.held)).toEqual(["a"]);
  });
});

describe("ended some other way", () => {
  test("its app withdrew it: it can't come back", () => {
    const [a, b, c] = ["a", "b", "c"].map(n => mk(n));
    let { batch } = take(null, "center", [a, b, c], [a, b], all);
    batch = forget(batch, a);
    expect(names(batch.held)).toEqual(["b"]);
    expect(names(restore(batch, [c]))).toEqual(["b", "c"]);
    expect(forget(batch, b)).toBeNull();
  });

  test("forgetting what isn't held changes nothing", () => {
    const [a, b] = ["a", "b"].map(n => mk(n));
    const { batch } = take(null, "center", [a, b], [a], all);
    expect(forget(batch, b)).toBe(batch);
    expect(forget(null, b)).toBeNull();
  });
});

describe("the history file", () => {
  test("never holds a held item, even a toast still in the list", () => {
    const [a, b, c] = ["a", "b", "c"].map(n => mk(n));
    const { batch } = take(null, "center", [a, b, c], [b], all);
    expect(isHeld(batch, b)).toBe(true);
    expect(isHeld(batch, a)).toBe(false);
    expect(names(persisted([a, b, c], [], batch))).toEqual(["a", "c"]);
  });

  test("after Undo (no batch) everything is written again, discarded ones still not", () => {
    const [a, b] = ["a", "b"].map(n => mk(n));
    const gone = mk("gone", { discard: true });
    const s = mk("snoozed");
    expect(names(persisted([a, gone, b], [s], null))).toEqual(["a", "b", "snoozed"]);
  });

  test("a one-time code is never written, snoozed or not", () => {
    const [a, b] = ["a", "b"].map(n => mk(n));
    const code = mk("code", { otp: true }), later = mk("later", { otp: true });
    const secret = i => !!i.otp;
    expect(names(persisted([a, code, b], [later], null, secret))).toEqual(["a", "b"]);
    expect(names(persisted([a, code], [], null))).toEqual(["a", "code"]);
  });
});

describe("place", () => {
  test("nothing to put back: the list as it is", () => {
    const [a, b] = ["a", "b"].map(n => mk(n));
    expect(place([a, b], [a, b], [])).toEqual([a, b]);
  });
  test("into an empty list", () => {
    const [a, b] = ["a", "b"].map(n => mk(n));
    expect(place([], [a, b], [b, a])).toEqual([a, b]);
  });
});
