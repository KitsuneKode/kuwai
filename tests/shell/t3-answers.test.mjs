import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const src = readFileSync(new URL("../../shell/modules/island/AgentsPanel.qml", import.meta.url), "utf8");
const body = src.slice(src.indexOf("function answerT3("), src.indexOf("property bool inStrip"));

test("each answer starts its own process, which carries its own request", () => {
  expect(body).toMatch(/\.createObject\(ap, \{ asked: \{ id: r\.request\.id, decision: decision \}/);
  expect(body).not.toMatch(/t3AnswerProc|\.pending\s*=/);
  expect(body).toMatch(/const p = one\.asked;/);
});

test("the process outlives its output, then goes", () => {
  expect(body).toMatch(/onExited: destroy\(\d+\)/);
});
