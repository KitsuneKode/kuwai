import { describe, expect, test } from "bun:test";
import * as Tools from "../../shell/services/cacheTools.mjs";

const docker = {
  id: "docker", label: "Docker", bytes: 14578399947, tag: "check first", clearable: false,
  parts: [
    { id: "docker-images", label: "Unused images", bytes: 13840000000, command: "docker image prune", runnable: true, note: "a" },
    { id: "docker-builder", label: "Build cache", bytes: 2347, command: "docker builder prune", runnable: true, note: "b" },
    { id: "docker-containers", label: "Stopped containers", bytes: 297600, command: "docker container prune", runnable: false, note: "c" },
    { id: "docker-volumes", label: "Unused volumes", bytes: 738100000, command: "docker volume prune", runnable: false, note: "d" },
  ],
};

describe("partRows", () => {
  test("keeps each part's command and which ones can be run from here", () => {
    const rows = Tools.partRows(docker);
    expect(rows.map(r => r.id)).toEqual(["docker-images", "docker-builder", "docker-containers", "docker-volumes"]);
    expect(rows.filter(r => r.runnable).map(r => r.id)).toEqual(["docker-images", "docker-builder"]);
    expect(rows[3].command).toBe("docker volume prune");
  });
  test("a part is runnable only if its id is on the list, whatever the report says", () => {
    const forged = { parts: [
      { id: "docker-volumes", label: "v", bytes: 5, command: "docker volume prune", runnable: true },
      { id: "journal-system", label: "j", bytes: 5, command: "sudo journalctl --vacuum-time=2weeks", runnable: true },
      { id: "docker-images", label: "i", bytes: 5, command: "docker image prune", runnable: "yes" },
    ] };
    expect(Tools.partRows(forged).map(r => r.runnable)).toEqual([false, false, false]);
  });
  test("an item without parts, a missing item or junk parts give no rows and no error", () => {
    expect(Tools.partRows({ id: "pacman" })).toEqual([]);
    expect(Tools.partRows(null)).toEqual([]);
    expect(Tools.partRows({ parts: "x" })).toEqual([]);
    expect(Tools.partRows({ parts: [null, 3, { id: 1 }, { id: "a", command: "" }, { id: "a" }] })).toEqual([]);
  });
  test("sizes that are not numbers, negative or not finite are zero, never NaN", () => {
    const rows = Tools.partRows({ parts: [
      { id: "a", command: "x", bytes: "lots" }, { id: "b", command: "x", bytes: -4 },
      { id: "c", command: "x", bytes: Infinity }, { id: "d", command: "x" },
    ] });
    expect(rows.map(r => r.bytes)).toEqual([0, 0, 0, 0]);
    expect(rows.map(r => r.label)).toEqual(["a", "b", "c", "d"]);
  });
  test("very large sizes stay finite numbers", () => {
    const rows = Tools.partRows({ parts: [{ id: "a", command: "x", bytes: 2 ** 62 }, { id: "b", command: "x", bytes: 18446744073709551616 }] });
    expect(rows.every(r => Number.isFinite(r.bytes) && r.bytes > 0)).toBe(true);
    const sum = rows.reduce((n, r) => n + r.bytes, 0);
    expect(Number.isFinite(sum)).toBe(true);
  });
});

describe("unavailable", () => {
  test("a daemon that is down and a refused user each get one plain line", () => {
    expect(Tools.unavailable({ docker: { state: "down" } })).toBe("Docker isn't running, so what it holds isn't counted");
    expect(Tools.unavailable({ docker: { state: "denied" } })).toMatch(/docker group/);
  });
  test("working, not installed, or an older report say nothing", () => {
    for (const r of [{ docker: { state: "ok" } }, { docker: { state: "missing" } }, {}, null, undefined, { docker: {} }])
      expect(Tools.unavailable(r)).toBe("");
  });
  test("the lines never name an exit status, a path or a helper", () => {
    for (const s of ["down", "denied"]) expect(Tools.unavailable({ docker: { state: s } })).not.toMatch(/exit|\/|kuwai|undefined|NaN/i);
  });
});

describe("clearableBytes", () => {
  test("counts only items that clear in one click: never check-first ones", () => {
    const items = [docker, { id: "bun", bytes: 100, clearable: true }, { id: "npm", bytes: 50, clearable: true }, { id: "trash", bytes: 999, clearable: false }];
    expect(Tools.clearableBytes(items)).toBe(150);
  });
  test("nothing, or junk, is zero", () => {
    expect(Tools.clearableBytes([])).toBe(0);
    expect(Tools.clearableBytes(undefined)).toBe(0);
    expect(Tools.clearableBytes([null, { clearable: true, bytes: "x" }])).toBe(0);
  });
});
