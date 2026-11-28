import { describe, expect, test } from "bun:test";
import * as A from "../../shell/services/activity.mjs";
import { functions } from "../helpers/qml.mjs";

const MB = 1048576;
const unit = (name, over = {}) => ({
  unit: name, id: name.replace(/^app-|-\d+\.scope$/g, ""), launcher: "", label: name.replace(/^app-|-\d+\.scope$/g, ""),
  main: "x", pid: 10, start: 5, procs: 2, cpu: 0, mem: 100 * MB, protected: false, ...over,
});
const frame = (units, cpus = 16) => A.parseFrame(JSON.stringify({ t: 1, cpus, units }));

describe("parseFrame", () => {
  test("reads a frame and fills what the helper left out", () => {
    const f = A.parseFrame('{"cpus":8,"units":[{"unit":"app-a-1.scope","id":"a","label":"A","procs":3,"cpu":12.5,"mem":1048576,"protected":true}]}');
    expect(f.cpus).toBe(8);
    expect(f.units[0]).toMatchObject({ key: "app-a-1.scope", unit: "app-a-1.scope", label: "A", procs: 3, cpu: 12.5, mem: 1048576, protected: true, launcher: "", main: "" });
  });
  test("memory the helper could not read is -1, not zero", () => {
    expect(A.parseFrame('{"cpus":1,"units":[{"unit":"app-a-1.scope","mem":null}]}').units[0].mem).toBe(-1);
    expect(A.parseFrame('{"cpus":1,"units":[{"unit":"app-a-1.scope"}]}').units[0].mem).toBe(-1);
  });
  test("rubbish is refused, not thrown", () => {
    for (const bad of ["", "not json", "null", "[]", '{"units":3}', '{"cpus":1}']) expect(A.parseFrame(bad)).toBeNull();
  });
  test("an entry without a unit name is dropped and numbers are kept sane", () => {
    const f = A.parseFrame('{"cpus":0,"units":[{"id":"x"},{"unit":""},{"unit":"app-b-1.scope","cpu":-4,"procs":0,"label":""}]}');
    expect(f.cpus).toBe(1);
    expect(f.units.map(u => u.unit)).toEqual(["app-b-1.scope"]);
    expect(f.units[0]).toMatchObject({ cpu: 0, procs: 1, label: "app-b-1.scope" });
  });
  test("a name is whatever the helper said: text, never markup to be parsed", () => {
    const f = A.parseFrame(JSON.stringify({ cpus: 1, units: [{ unit: "app-x-1.scope", label: "<img src=https://example.com/a.png>" }] }));
    expect(f.units[0].label).toBe("<img src=https://example.com/a.png>");
  });
});

describe("rank and step", () => {
  test("busiest first by the percent that is shown, then more memory, then name", () => {
    const f = frame([unit("app-b-1.scope", { cpu: 0.2, mem: 5 * MB, label: "B" }), unit("app-a-1.scope", { cpu: 0.4, mem: 5 * MB, label: "A" }),
      unit("app-c-1.scope", { cpu: 0, mem: 900 * MB, label: "C" }), unit("app-d-1.scope", { cpu: 30, label: "D" })]);
    const s = A.step(A.empty(), f);
    expect(s.keys).toEqual(["app-d-1.scope", "app-c-1.scope", "app-a-1.scope", "app-b-1.scope"]);
  });
  test("rows keep their places between beats, newcomers go to the end, the gone are dropped", () => {
    let s = A.step(A.empty(), frame([unit("app-a-1.scope", { cpu: 50 }), unit("app-b-1.scope", { cpu: 40 }), unit("app-c-1.scope", { cpu: 30 })]));
    s = A.step(s, frame([unit("app-a-1.scope", { cpu: 1 }), unit("app-b-1.scope", { cpu: 90 }), unit("app-c-1.scope", { cpu: 30 }), unit("app-n-1.scope", { cpu: 99 })]));
    expect(s.keys).toEqual(["app-a-1.scope", "app-b-1.scope", "app-c-1.scope", "app-n-1.scope"]);
    s = A.step(s, frame([unit("app-n-1.scope", { cpu: 99 }), unit("app-a-1.scope", { cpu: 1 })]));
    expect(s.keys).toEqual(["app-a-1.scope", "app-n-1.scope"]);
  });
  test("on the beat the list sorts again; a frozen list (hovered or armed) does not", () => {
    const start = A.step(A.empty(), frame([unit("app-a-1.scope", { cpu: 50 }), unit("app-b-1.scope", { cpu: 40 })]));
    let s = start, moved = frame([unit("app-a-1.scope", { cpu: 1 }), unit("app-b-1.scope", { cpu: 80 })]);
    for (let i = 1; i < A.BEAT; i++) { s = A.step(s, moved); expect(s.keys).toEqual(["app-a-1.scope", "app-b-1.scope"]); }
    expect(A.step(s, moved).keys).toEqual(["app-b-1.scope", "app-a-1.scope"]);
    expect(A.step(s, moved, { freeze: true }).keys).toEqual(["app-a-1.scope", "app-b-1.scope"]);
  });
  test("an empty frame is an empty list, and the next frame sorts afresh", () => {
    let s = A.step(A.empty(), frame([unit("app-a-1.scope", { cpu: 5 })]));
    s = A.step(s, frame([]));
    expect(s.keys).toEqual([]);
    s = A.step(s, frame([unit("app-z-1.scope", { cpu: 1 }), unit("app-y-1.scope", { cpu: 9 })]));
    expect(s.keys).toEqual(["app-y-1.scope", "app-z-1.scope"]);
  });
  test("the machine's thread count comes with the frame", () => {
    expect(A.step(A.empty(), frame([], 24)).cpus).toBe(24);
  });
});

describe("diff", () => {
  const apply = (list, ops) => {
    const out = list.slice();
    for (const o of ops) {
      if (o.op === "remove") out.splice(o.at, 1);
      else if (o.op === "move") out.splice(o.to, 0, out.splice(o.from, 1)[0]);
      else out.splice(o.at, 0, o.key);
    }
    return out;
  };
  test("turns one list into another with removes, moves and inserts", () => {
    const cases = [[[], ["a"]], [["a"], []], [["a", "b", "c"], ["c", "b", "a"]], [["a", "b", "c"], ["b", "x", "a"]], [["a", "b"], ["a", "b"]]];
    for (const [from, to] of cases) expect(apply(from, A.diff(from, to))).toEqual(to);
  });
  test("nothing to do is no edits", () => { expect(A.diff(["a", "b"], ["a", "b"])).toEqual([]); });
  test("any shuffle, any churn, ends where it should (and a row that stays is never removed)", () => {
    let seed = 7;
    const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
    const pool = Array.from({ length: 14 }, (_, i) => "k" + i);
    for (let n = 0; n < 300; n++) {
      const pick = () => pool.filter(() => rnd() < 0.6).sort(() => rnd() - 0.5);
      const from = pick(), to = pick();
      const ops = A.diff(from, to);
      expect(apply(from, ops)).toEqual(to);
      for (const o of ops) if (o.op === "remove") expect(to).not.toContain(from[o.at] ?? "");
    }
  });
});

describe("what a row says", () => {
  test("CPU is a whole percent of one thread", () => {
    expect(A.cpuText(0)).toBe("0%");
    expect(A.cpuText(0.4)).toBe("0%");
    expect(A.cpuText(37.5)).toBe("38%");
    expect(A.cpuText(1234)).toBe("1234%");
  });
  test("memory in the unit a person reads", () => {
    expect(A.memText(-1)).toBe("");
    expect(A.memText(0)).toBe("0 B");
    expect(A.memText(512 * 1024)).toBe("524 kB");
    expect(A.memText(310 * MB)).toBe("325 MB");
    expect(A.memText(1.5 * 1024 * MB)).toBe("1.6 GB");
    expect(A.memText(28 * 1024 * MB)).toBe("30 GB");
  });
  test("the tone follows the share of the whole machine, like the cores' bars", () => {
    expect(A.cpuTone(100, 16)).toBe("");
    expect(A.cpuTone(1200, 16)).toBe("orange");
    expect(A.cpuTone(1500, 16)).toBe("red");
    expect(A.cpuTone(95, 1)).toBe("red");
    expect(A.cpuTone(500, 0)).toBe("red");
  });
  test("process counts agree with their number", () => {
    expect(A.detail({ procs: 1 })).toBe("1 process");
    expect(A.detail({ procs: 31 })).toBe("31 processes");
  });
});

describe("stop and force quit", () => {
  const none = A.nothingArmed();
  test("Stop acts at once and disarms whatever was armed", () => {
    expect(A.press({ key: "a", action: "force" }, "a", "stop")).toEqual({ armed: none, fire: true });
  });
  test("Force quit takes two presses on the same row", () => {
    const first = A.press(none, "a", "force");
    expect(first).toEqual({ armed: { key: "a", action: "force" }, fire: false });
    expect(A.press(first.armed, "a", "force")).toEqual({ armed: none, fire: true });
  });
  test("pressing Force quit on another row arms that one; the first is no longer armed", () => {
    const armed = A.press(none, "a", "force").armed;
    const other = A.press(armed, "b", "force");
    expect(other).toEqual({ armed: { key: "b", action: "force" }, fire: false });
    expect(A.press(other.armed, "a", "force").fire).toBe(false);
  });
  test("a row that left takes its arming with it", () => {
    expect(A.keepArmed({ key: "a", action: "force" }, ["b"])).toEqual(none);
    const armed = { key: "a", action: "force" };
    expect(A.keepArmed(armed, ["a", "b"])).toBe(armed);
  });
  test("what a stop says afterwards, with no helper, exit status or path in it", () => {
    expect(A.outcome({ ok: true, gone: true }, "Zen")).toBe("");
    expect(A.outcome({ ok: true, gone: false, why: "it's still running; force quit ends it" }, "Zen")).toBe("Still running");
    expect(A.outcome({ ok: false, why: "your session needs it" }, "Zen")).toBe("Couldn't stop Zen: your session needs it");
    expect(A.outcome({}, "Zen")).toBe("Couldn't stop Zen");
    expect(A.noteWarns("Still running")).toBe(true);
    expect(A.noteWarns("Couldn't stop Zen")).toBe(true);
    expect(A.noteWarns("Stopping…")).toBe(false);
  });
});

describe("which face", () => {
  test("one at a time: an error beats everything, loading until the first frame, then empty or the list", () => {
    expect(A.viewState({ failed: true, ready: true, count: 4 })).toBe("error");
    expect(A.viewState({ failed: false, ready: false, count: 0 })).toBe("loading");
    expect(A.viewState({ failed: false, ready: true, count: 0 })).toBe("empty");
    expect(A.viewState({ failed: false, ready: true, count: 3 })).toBe("list");
  });
});

function service() {
  const model = [];
  const rowModel = {
    get count() { return model.length; },
    remove(i) { model.splice(i, 1); },
    move(from, to) { model.splice(to, 0, model.splice(from, 1)[0]); },
    insert(i, row) { model.splice(i, 0, row); },
    set(i, row) { model[i] = row; },
    clear() { model.length = 0; },
  };
  const s = functions("shell/services/Activity.qml", ["clear", "take", "show", "feed", "rowOf", "render", "press", "end", "ended"], {
    A, rowModel, ready: false, failed: false, hold: false, cpus: 1, armedKey: "", armedAction: "", snap: A.empty(), notes: {}, shown: [], last: {},
    lastAt: 0, crashes: 0, busy: false, watchers: 0, JSON, Date, Object,
    disarm: { restart() { s.disarmed = false; }, stop() { s.disarmed = true; } },
    ender: { running: false, key: "", name: "", command: [] }, Paths: { bin: "/bin" },
  });
  s.model = model;
  return s;
}

describe("the service's model", () => {
  const f = (units) => ({ t: 1, cpus: 16, units: units.map(u => ({ id: "x", label: "X", procs: 1, mem: 10, ...u })) });
  test("frames fill a list model in place: a row keeps its index entry as numbers change", () => {
    const s = service();
    s.show(f([{ unit: "app-a-1.scope", cpu: 50 }, { unit: "app-b-1.scope", cpu: 10 }]));
    expect(s.model.map(r => r.key)).toEqual(["app-a-1.scope", "app-b-1.scope"]);
    s.show(f([{ unit: "app-a-1.scope", cpu: 12 }, { unit: "app-b-1.scope", cpu: 70 }]));
    expect(s.model.map(r => [r.key, r.cpuText])).toEqual([["app-a-1.scope", "12%"], ["app-b-1.scope", "70%"]]);
    expect(s.ready).toBe(true);
  });
  test("a vanished app leaves the list and takes its note and arming", () => {
    const s = service();
    s.show(f([{ unit: "app-a-1.scope" }, { unit: "app-b-1.scope" }]));
    s.press("app-b-1.scope", "force", "B");
    expect(s.armedKey).toBe("app-b-1.scope");
    s.show(f([{ unit: "app-a-1.scope" }]));
    expect(s.model.map(r => r.key)).toEqual(["app-a-1.scope"]);
    expect(s.armedKey).toBe("");
  });
  test("an app the session lives on is shown locked, and Stop or Force quit never start for it", () => {
    const s = service();
    s.show(f([{ unit: "app-p-1.scope", protected: true }]));
    expect(s.model[0].locked).toBe(true);
    s.press("app-p-1.scope", "stop", "P");
    s.press("app-p-1.scope", "force", "P");
    s.press("app-p-1.scope", "force", "P");
    expect(s.ender.command).toEqual([]);
    expect(s.ender.running).toBe(false);
  });
  test("Stop runs the helper for that unit as arguments; Force quit needs two presses", () => {
    const s = service();
    s.show(f([{ unit: "app-a b;rm -rf-1.scope" }]));
    s.press("app-a b;rm -rf-1.scope", "stop", "A");
    expect(s.ender.command).toEqual(["/bin/kuwai-procs", "--end-unit", "app-a b;rm -rf-1.scope"]);
    expect(s.model[0].note).toBe("Stopping…");
    s.ender.running = false; s.ender.command = [];
    s.press("app-a b;rm -rf-1.scope", "force", "A");
    expect(s.ender.command).toEqual([]);
    expect(s.armedAction).toBe("force");
    s.press("app-a b;rm -rf-1.scope", "force", "A");
    expect(s.ender.command).toEqual(["/bin/kuwai-procs", "--end-unit", "app-a b;rm -rf-1.scope", "--force"]);
    expect(s.model[0].note).toBe("Quitting…");
  });
  test("an app that ignores Stop says so, and the note goes when the app does", () => {
    const s = service();
    s.show(f([{ unit: "app-a-1.scope" }]));
    s.ended("app-a-1.scope", "A", { ok: true, gone: false });
    expect(s.model[0].note).toBe("Still running");
    s.show(f([]));
    expect(s.notes).toEqual({});
  });
  test("leaving the tab empties everything the next opening would otherwise show", () => {
    const s = service();
    s.show(f([{ unit: "app-a-1.scope" }]));
    s.press("app-a-1.scope", "force", "A");
    s.clear();
    expect(s.model).toEqual([]);
    expect([s.ready, s.failed, s.armedKey, s.shown]).toEqual([false, false, "", []]);
  });
  test("a line that is not a frame changes nothing", () => {
    const s = service();
    s.take("garbage");
    expect(s.ready).toBe(false);
  });
});
