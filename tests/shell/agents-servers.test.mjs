import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { functions } from "../helpers/qml.mjs";

const path = "shell/modules/island/AgentsPanel.qml";

function scope() {
  return functions(path, ["age", "serverSubline"], {});
}

test("localhost listeners stay quiet and network listeners say so", () => {
  const s = scope();
  const server = { project: "shop", agent: "Codex", age: 90, local: true };
  expect(s.serverSubline(server)).toBe("shop · from Codex · 2m");
  expect(s.serverSubline(Object.assign({}, server, { local: false }))).toBe("on this network · shop · from Codex · 2m");
});

test("the agents card is a peek and stopping lives only in the unified Ports service", () => {
  const src = readFileSync(new URL("../../" + path, import.meta.url), "utf8");
  expect(src).toContain('text: "All ports"');
  expect(src).toContain('Ports.openUrl');
  expect(src).toContain('Island.openSystem("ports")');
  expect(src).not.toContain("stopServer");
  expect(src).not.toContain("Force stop");
  expect(src).not.toContain("kuwai-procs");
});
