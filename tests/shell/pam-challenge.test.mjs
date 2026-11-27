import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const read = p => readFileSync(new URL("../../" + p, import.meta.url), "utf8");

test("the lock gives the password only to a password prompt, and asks any other", () => {
  const src = read("shell/modules/lock/Lock.qml");
  expect(src).toMatch(/PamTurn\.kind\(message, responseVisible\) === "password"\) \{\s*if \(root\.held === ""\) \{ root\.asked = true/);
  expect(src).toMatch(/root\.challenge = PamTurn\.label\(message\)/);
  expect(src).toMatch(/if \(challenge !== ""\) \{[\s\S]*?pam\.respond\(answer\);/);
  expect(src).not.toMatch(/answers\+\+ === 0/);
});

test("the login screen does the same with greetd", () => {
  const src = read("shell/greeter.qml");
  expect(src).toMatch(/k === "password" && root\.held !== ""/);
  expect(src).toMatch(/if \(challenge !== ""\) \{[\s\S]*?Greetd\.respond\(answer\);/);
  expect(src).not.toMatch(/answers\+\+ === 0/);
});

test("the field shows the question while one is waiting", () => {
  expect(read("shell/modules/lock/PasswordPill.qml")).toContain("entry.lock.challenge ? entry.lock.challenge");
  expect(read("shell/modules/lock/LockView.qml")).toContain("view.lock.challenge ? view.lock.challenge");
});
