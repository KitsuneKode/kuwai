import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const read = p => readFileSync(new URL("../../" + p, import.meta.url), "utf8");

test("the lock answers only PAM's first question with the password, and asks the next", () => {
  const src = read("shell/modules/lock/Lock.qml");
  expect(src).toMatch(/if \(root\.answers\+\+ === 0\) \{ respond\(root\.password\); return; \}/);
  expect(src).toMatch(/root\.challenge = String\(message \|\| "Verification code"\)/);
  expect(src).toMatch(/if \(challenge !== ""\) \{[\s\S]*?pam\.respond\(answer\);/);
});

test("the login screen does the same with greetd", () => {
  const src = read("shell/greeter.qml");
  expect(src).toMatch(/if \(root\.answers\+\+ === 0\) \{ Greetd\.respond\(root\.password\); return; \}/);
  expect(src).toMatch(/if \(challenge !== ""\) \{[\s\S]*?Greetd\.respond\(answer\);/);
});

test("the field shows the question while one is waiting", () => {
  expect(read("shell/modules/lock/PasswordPill.qml")).toContain("entry.lock.challenge ? entry.lock.challenge");
  expect(read("shell/modules/lock/LockView.qml")).toContain("view.lock.challenge ? view.lock.challenge");
});
