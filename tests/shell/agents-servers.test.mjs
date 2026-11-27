import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { functions } from "../helpers/qml.mjs";

const path = "shell/modules/island/AgentsPanel.qml";

function scope() {
  return functions(path, ["age", "forceFor", "serverSubline", "stopServer"], {
    Paths: { bin: "BIN" },
    stopArmed: 0,
    stopStart: "",
    forcePid: 0,
    forceStart: "",
    stopDisarm: { restarted: 0, stopped: 0, restart() { this.restarted++; }, stop() { this.stopped++; } },
    stopProc: { who: "", pid: 0, start: "", running: false, command: [] }
  });
}

test("the first confirmed stop sends SIGTERM and never SIGKILL", () => {
  const s = scope();
  const server = { pid: 42, start: 99, port: 3000 };
  s.stopServer(server);
  expect(s.stopArmed).toBe(42);
  expect(s.stopDisarm.restarted).toBe(1);
  expect(s.stopProc.command).toEqual([]);
  s.stopServer(server);
  expect(s.stopProc.command).toEqual(["BIN/kuwai-procs", "--end", "42", "--start", "99"]);
  expect(s.stopProc.command).not.toContain("--force");
});

test("only a server that ignored the grace gets the Force stop path", () => {
  const s = scope();
  const server = { pid: 42, start: 99, port: 3000 };
  s.forcePid = 42;
  s.forceStart = "99";
  s.stopServer(server);
  expect(s.stopProc.command).toEqual(["BIN/kuwai-procs", "--end", "42", "--start", "99", "--force"]);
  expect(s.forcePid).toBe(0);
});

test("a reused process number does not inherit another server's force state", () => {
  const s = scope();
  s.forcePid = 42;
  s.forceStart = "99";
  expect(s.forceFor({ pid: 42, start: 100 })).toBe(false);
  expect(s.forceFor({ pid: 42, start: 99 })).toBe(true);
});

test("localhost listeners stay quiet and network listeners say so", () => {
  const s = scope();
  const server = { project: "shop", agent: "Codex", age: 90, local: true };
  expect(s.serverSubline(server)).toBe("shop · from Codex · 2m");
  expect(s.serverSubline(Object.assign({}, server, { local: false }))).toBe("on this network · shop · from Codex · 2m");
});

test("a still-running answer is what exposes the force action", () => {
  const src = readFileSync(new URL("../../" + path, import.meta.url), "utf8");
  expect(src).toContain('r.gone === false');
  expect(src).toContain('"Force stop"');
});
