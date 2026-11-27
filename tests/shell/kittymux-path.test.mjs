import { expect, test } from "bun:test";
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { functions } from "../helpers/qml.mjs";

const path = "shell/services/Kittymux.qml";

function service(bin) {
  const commands = [];
  const make = (parent, opts) => {
    commands.push(opts.command);
    return { running: false };
  };
  const s = functions(path, ["muxBin", "act", "jumpEvent", "ack", "ackAll", "openPanel", "run", "safeKey", "canAnswer", "setAnswer", "answer"], {
    bin,
    commands,
    asks: ({}),
    answers: ({}),
    answerDry: false,
    runner: { createObject: make },
    answerer: { createObject: make },
    replier: { createObject: make }
  });
  return s;
}

test("the executable is PATH resolution until the probe finds it", () => {
  const s = service("");
  expect(s.muxBin()).toBe("kittymux");
  s.bin = "/fake-path/kittymux";
  expect(s.muxBin()).toBe("/fake-path/kittymux");
});

test("every service action invokes the PATH-discovered executable", () => {
  const s = service("/fake-path/kittymux");
  s.act({ op: "jump", pid: 7, w: "2" });
  s.jumpEvent("evt");
  s.ack("evt");
  s.ackAll();
  s.openPanel();
  expect(s.commands.map(c => c[0])).toEqual(Array(5).fill("/fake-path/kittymux"));
  expect(s.commands[0].slice(1)).toEqual(["act", JSON.stringify({ op: "jump", pid: 7, w: "2" })]);
  expect(s.commands[1].slice(1)).toEqual(["inbox", "jump", "evt"]);
  expect(s.commands[2].slice(1)).toEqual(["inbox", "ack", "evt"]);
  expect(s.commands[3].slice(1)).toEqual(["inbox", "ack", "--all"]);
  expect(s.commands[4].slice(1)).toEqual(["panel", "toggle"]);
});

test("the typed-prompt answer uses the same discovered executable", () => {
  const s = service("/fake-path/kittymux");
  s.answer({ key: "w7.2", agent: "claude", needs: true, question: "Allow Bash?" }, "allow");
  const cmd = s.commands[0];
  expect(cmd[0]).toBe("/fake-path/kittymux");
  expect(cmd.slice(1)).toEqual(["answer", "w7.2", "allow", "--expect", "Allow Bash?"]);
});


test("a notification jump invokes the same discovered executable", () => {
  const commands = [];
  const n = functions("shell/services/Notifs.qml", ["jumpTo"], {
    Kittymux: { muxBin: () => "/fake-path/kittymux" },
    jumper: { createObject: (parent, opts) => { commands.push(opts.command); return { running: false }; } }
  });
  n.jumpTo({ jump: "7:2", notification: { dismiss() {} } });
  expect(commands).toEqual([["/fake-path/kittymux", "act", JSON.stringify({ op: "jump", pid: 7, w: "2" })]]);
});

test("the production probe really finds a kittymux only present on PATH", () => {
  const dir = mkdtempSync(join(tmpdir(), "kuwai-kittymux-"));
  const bin = join(dir, "kittymux");
  writeFileSync(bin, "#!/bin/sh\nexit 0\n");
  chmodSync(bin, 0o755);
  const src = readFileSync(new URL("../../" + path, import.meta.url), "utf8");
  const probe = src.match(/command: \["sh", "-c", "(command -v kittymux)"\]/);
  expect(probe).not.toBeNull();
  const r = spawnSync("/bin/sh", ["-c", probe[1]], { encoding: "utf8", env: { PATH: dir } });
  expect(r.status).toBe(0);
  expect(r.stdout.trim()).toBe(bin);
});

test("no runtime call site assumes a home or project path", () => {
  const files = [
    "shell/services/Kittymux.qml",
    "shell/services/Notifs.qml",
    "shell/modules/island/LauncherPanel.qml"
  ];
  for (const f of files) {
    const src = readFileSync(new URL("../../" + f, import.meta.url), "utf8");
    expect(src).not.toContain(".local/bin/kittymux");
    expect(src).not.toContain("Projects/kittymux");
  }
  expect(readFileSync(new URL("../../shell/services/Notifs.qml", import.meta.url), "utf8")).toContain("Kittymux.muxBin()");
  expect(readFileSync(new URL("../../shell/modules/island/LauncherPanel.qml", import.meta.url), "utf8")).toContain("command -v kittymux");
  const service = readFileSync(new URL("../../" + path, import.meta.url), "utf8");
  expect(service).toContain('command: [root.muxBin(), "pick", "--json"]');
});
