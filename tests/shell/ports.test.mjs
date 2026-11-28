import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { ageText, compare, empty, keepArmed, monogram, openable, parseRows, phase, press, scopeOf, step } from "../../shell/services/ports.mjs";

function raw(extra = {}) {
  return Object.assign({
    port: 3000, host: "127.0.0.1", proc: "node", what: "next dev", project: "shop", pid: 42, start: 99,
    age: 125, agent: "Codex", parentApp: "Kitty", memBytes: 1536000, cpu: 12.4, local: true
  }, extra);
}

test("rows keep a stable pid and start identity and expose host-derived scope", () => {
  const rows = parseRows(JSON.stringify([raw()]));
  expect(rows).not.toBeNull();
  expect(rows[0].key).toBe("42:99");
  expect(rows[0].scope).toBe("local");
  expect(rows[0].memText).toBe("2 MB");
  expect(rows[0].sub).toBe("next dev · Codex · inside Kitty · 2m");
  expect(scopeOf("192.168.1.20")).toBe("lan");
  expect(scopeOf("::1")).toBe("local");
});

test("malformed helper output is an error, never an empty list", () => {
  expect(parseRows("not json")).toBeNull();
  expect(parseRows("{}")).toBeNull();
  expect(parseRows("[]")).toEqual([]);
});

test("framework monograms use product initials and unknown servers use two letters", () => {
  expect(monogram("next dev", "node")).toBe("NX");
  expect(monogram("vite", "node")).toBe("VT");
  expect(monogram("astro dev", "node")).toBe("AS");
  expect(monogram("bun dev", "bun")).toBe("BN");
  expect(monogram("uvicorn", "python3")).toBe("PY");
  expect(monogram("postgres", "postgres")).toBe("PG");
  expect(monogram("redis-server", "redis-server")).toBe("RD");
  expect(monogram("docker-proxy", "docker-proxy")).toBe("DK");
  expect(monogram("caddy", "caddy")).toBe("CA");
});

test("wildcard and loopback listeners may open localhost, LAN-only ones may not", () => {
  expect(openable("0.0.0.0")).toBe(true);
  expect(openable("::")).toBe(true);
  expect(openable("127.0.0.1")).toBe(true);
  expect(openable("192.168.1.20")).toBe(false);
});

test("a hovered or armed row freezes the sorted order until the hold ends", () => {
  const a = parseRows(JSON.stringify([raw(), raw({ port: 3001, pid: 43, start: 100 })]));
  let snap = step(empty(), a, { sortKey: "port", sortDir: 1 });
  expect(snap.keys).toEqual(["42:99", "43:100"]);
  const busy = parseRows(JSON.stringify([raw({ port: 3001, pid: 43, start: 100 }), raw()]));
  snap = step(snap, busy, { sortKey: "memory", sortDir: -1, freeze: true });
  expect(snap.keys).toEqual(["42:99", "43:100"]);
  snap = step(snap, busy, { sortKey: "memory", sortDir: -1, freeze: false });
  expect(snap.keys).toEqual(["42:99", "43:100"]);
});

test("sort order changes only on the slow beat unless the list is fresh", () => {
  const rows = parseRows(JSON.stringify([
    raw({ port: 3002, pid: 44, start: 101, cpu: 1 }),
    raw({ port: 3000, cpu: 30 }),
    raw({ port: 3001, pid: 43, start: 100, cpu: 10 })
  ]));
  let snap = step(empty(), rows, { sortKey: "cpu", sortDir: -1 });
  expect(snap.keys).toEqual(["42:99", "43:100", "44:101"]);
  expect(compare(rows[1], rows[0], "port", 1)).toBeLessThan(0);
});

test("stop and force both arm first and fire only on the same second press", () => {
  let r = press({ key: "", action: "" }, "42:99", "stop");
  expect(r.fire).toBe(false);
  expect(r.armed).toEqual({ key: "42:99", action: "stop" });
  r = press(r.armed, "42:99", "stop");
  expect(r.fire).toBe(true);
  r = press({ key: "", action: "" }, "42:99", "force");
  expect(r.fire).toBe(false);
  r = press(r.armed, "42:99", "force");
  expect(r.fire).toBe(true);
  expect(keepArmed({ key: "42:99", action: "stop" }, [])).toEqual({ key: "", action: "" });
});

test("phase names loading, empty, error and ready distinctly", () => {
  expect(phase({ failed: false, ready: false, count: 0 })).toBe("loading");
  expect(phase({ failed: false, ready: true, count: 0 })).toBe("empty");
  expect(phase({ failed: true, ready: true, count: 3 })).toBe("error");
  expect(phase({ failed: false, ready: true, count: 3 })).toBe("ready");
});

test("ages and the service stop path are safe and speak plainly", () => {
  expect(ageText(20)).toBe("now");
  expect(ageText(120)).toBe("2m");
  const src = readFileSync(new URL("../../shell/services/Ports.qml", import.meta.url), "utf8");
  expect(src).toContain('"--end"');
  expect(src).toContain('"--start"');
  expect(src).not.toContain("--end-unit");
  expect(src).not.toContain("SIGTERM");
  expect(src).not.toContain("SIGKILL");
});
