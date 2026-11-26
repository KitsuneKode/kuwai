import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { functions } from "../helpers/qml.mjs";
import { WORDS, believed, isPrompt } from "../../shell/services/authWords.mjs";

const cmd = (...args) => args.join("\u0000") + "\u0000";
const prompt = cmd("/usr/bin/qs", "-p", "/usr/local/share/kuwai/shell-auth");

test("every phrase the prompt can write is one the island shows, and no other", () => {
  const src = readFileSync(new URL("../../shell-auth/shell.qml", import.meta.url), "utf8");
  const ids = [...src.slice(src.indexOf("function describe")).matchAll(/"(org\.freedesktop\.[\w.-]+)":/g)].map(m => m[1]);
  expect(ids.length).toBeGreaterThan(5);
  const said = new Set();
  for (const message of ["Authentication is needed to run `/usr/local/lib/kuwai/kuwai-update-root' as the super user", "anything else"])
    for (const id of [...ids, "org.example.unknown"])
      said.add(functions("shell-auth/shell.qml", ["describe"], { message }).describe(id));
  expect([...said].sort()).toEqual([...WORDS].sort());
});

const unit = "0::/user.slice/user-1000.slice/user@1000.service/session.slice/kuwai-auth.service\n";
const stable = "/home/me/.local/share/kuwai/shell-auth";

test("the prompt's own words from the prompt's own process", () => {
  expect(believed("Install updates", prompt, unit, stable)).toBe("Install updates");
  expect(believed("Install updates", cmd("/usr/bin/qs", "-p", stable + "/"), unit, stable)).toBe("Install updates");
});

test("words of a writer's own choosing never show", () => {
  expect(believed("Enter your password to keep your files", prompt, unit, stable)).toBe("");
  expect(believed("", prompt, unit, stable)).toBe("");
});

test("a copy of the prompt elsewhere, another qs, or another unit is not the prompt", () => {
  expect(isPrompt(cmd("/usr/bin/qs", "-p", "/tmp/x/shell-auth"), unit, stable)).toBe(false);
  expect(isPrompt(cmd("/home/me/bin/qs", "-p", "/usr/local/share/kuwai/shell-auth"), unit, stable)).toBe(false);
  expect(isPrompt(prompt, "0::/user.slice/user-1000.slice/user@1000.service/app.slice/evil.scope\n", stable)).toBe(false);
  expect(isPrompt(cmd("/usr/bin/qs", "-p", "/home/me/.local/share/kuwai/shell"), unit, stable)).toBe(false);
  expect(isPrompt(cmd("/usr/bin/python3", "fake.py", "-p", "/x/shell-auth"), unit, stable)).toBe(false);
  expect(isPrompt("", unit, stable)).toBe(false);
});
