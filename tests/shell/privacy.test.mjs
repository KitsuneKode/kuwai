// Privacy rules that live in QML, tested from the QML source itself (no
// copy to drift): verification codes on the lock screen (review 2026-11-10,
// finding 06) and sharing before urgency (finding 04).
//   bun test tests/shell/privacy.test.mjs
import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const root = new URL("../../shell/", import.meta.url);
const src = (p) => readFileSync(new URL(p, root), "utf8");
const notifs = src("services/Notifs.qml"), lock = src("modules/lock/LockNotifs.qml");
// One QML function, by name, as JS source (brace-matched).
const grab = (s, name) => {
  const i = s.indexOf("function " + name + "(");
  if (i < 0) throw new Error("no function " + name);
  for (let k = s.indexOf("{", i), d = 0; k < s.length; k++) {
    if (s[k] === "{") d++;
    else if (s[k] === "}" && --d === 0) return s.slice(i, k + 1);
  }
};
const regexProp = (s, name) => eval(s.match(new RegExp("property var " + name + ": (/.*/[a-z]*)"))[1]);

const otpOf = eval("(" + grab(notifs, "otpOf") + ")");
const Notifs = { otpOf };
const codeWords = regexProp(lock, "codeWords"), codeShape = regexProp(lock, "codeShape");
const isCode = eval("(" + grab(lock, "isCode") + ")");
const heading = eval("(" + grab(lock, "heading") + ")");
const preview = eval("(" + grab(lock, "preview") + ")");

describe("lock screen codes", () => {
  const codes = [
    { app: "Google", title: "Verification", body: "Your code is 123 456" },
    { app: "Bank", title: "Security PIN", body: "Your Security PIN is 4821" },
    { app: "Mail", title: "482913 is your code", body: "" },
    { app: "GitHub", title: "Sign in", body: "Use 77F3K9QA to sign in" },
  ];
  for (const i of codes)
    test("hides " + JSON.stringify(i.body || i.title), () => {
      expect(isCode(i)).toBe(true);
      expect(preview(i)).toBe("Code hidden · unlock to see");
    });
  test("a code in the title hides the title", () => expect(heading(codes[2])).toBe("Mail · code"));
  test("anything otpOf finds is a code on the lock too", () => {
    for (const i of codes) if (otpOf(i)) expect(isCode(i)).toBe(true);
  });
  for (const i of [{ app: "Slack", title: "Anna", body: "lunch at 12?" }, { app: "Calendar", title: "Meeting", body: "Room 2026 at 3pm" }])
    test("leaves " + JSON.stringify(i.body) + " alone", () => expect(isCode(i)).toBe(false));
});

describe("sharing before urgency", () => {
  const make = (sharing, redactSensitive = true) => eval(`(() => {
    const sharing = ${sharing};
    const Settings = { notifRedactSensitive: ${redactSensitive} };
    const sensitiveApps = /\\b(zapzap|whatsapp|telegram|signal|discord|slack|element|messenger|beeper)\\b/i;
    return (${grab(notifs, "bodyRedacted")});
  })()`);
  test("a critical body is hidden while sharing", () => expect(make(true)({ app: "Bank", severity: "critical", body: "x" })).toBe(true));
  test("a warning body is hidden while sharing", () => expect(make(true)({ app: "x", severity: "warning", body: "x" })).toBe(true));
  test("outside a share, critical and warning bodies show", () => {
    expect(make(false)({ app: "Signal", severity: "critical", body: "x" })).toBe(false);
    expect(make(false)({ app: "x", severity: "warning", body: "x" })).toBe(false);
  });
  test("a private chat is hidden outside a share", () => expect(make(false)({ app: "Signal", severity: "", body: "x" })).toBe(true));
});
