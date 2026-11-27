import { expect, test } from "bun:test";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const root = new URL("../../shell/", import.meta.url).pathname;
function files(dir) {
    return readdirSync(dir).flatMap(n => {
        const p = join(dir, n);
        if (statSync(p).isDirectory()) return n === "node_modules" ? [] : files(p);
        return /\.(m?js|qml)$/.test(n) ? [p] : [];
    });
}
const code = p => readFileSync(p, "utf8").split("\n").filter(l => !/^\s*\/\//.test(l)).join("\n");

test("no object spread: Qt's module loader rejects it and the file never loads", () => {
    const bad = files(root).filter(p => /\{\s*\.\.\.[A-Za-z_$]|,\s*\.\.\.[A-Za-z_$][\w.$]*\s*\}/.test(code(p)));
    expect(bad.map(p => p.slice(root.length))).toEqual([]);
});

test("no Unicode property classes in regular expressions: Qt's engine throws on them", () => {
    const bad = files(root).filter(p => /\\[pP]\{/.test(code(p)));
    expect(bad.map(p => p.slice(root.length))).toEqual([]);
});
