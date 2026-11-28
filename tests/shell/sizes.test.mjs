import { describe, expect, test } from "bun:test";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { bytes, compact, inGB, fromKiB, fromMiB } from "../../shell/services/sizes.mjs";

describe("bytes", () => {
    test("decimal units, the way GNOME and macOS print them", () => {
        expect(bytes(0)).toBe("0 B");
        expect(bytes(999)).toBe("999 B");
        expect(bytes(1000)).toBe("1 kB");
        expect(bytes(524288)).toBe("524 kB");
        expect(bytes(1e6)).toBe("1 MB");
        expect(bytes(325 * 1048576)).toBe("341 MB");
        expect(bytes(1.5e9)).toBe("1.5 GB");
        expect(bytes(16.24e9)).toBe("16 GB");
        expect(bytes(16.24e9, 100)).toBe("16.2 GB");
        expect(bytes(123.4e9, 100)).toBe("123 GB");
        expect(bytes(2.5e12)).toBe("2.5 TB");
        expect(bytes(25e12)).toBe("25 TB");
    });
    test("a number that rounds up to the next unit moves to it", () => {
        expect(bytes(999.6e3)).toBe("1 MB");
        expect(bytes(999.6e6)).toBe("1 GB");
    });
    test("a kibibyte is not a kilobyte", () => {
        expect(bytes(1024)).toBe("1 kB");
        expect(bytes(1048576)).toBe("1 MB");
        expect(bytes(1073741824)).toBe("1.1 GB");
    });
    test("nothing readable is zero", () => {
        expect(bytes(undefined)).toBe("0 B");
        expect(bytes(NaN)).toBe("0 B");
        expect(bytes(-5)).toBe("0 B");
        expect(bytes("2500000")).toBe("3 MB");
    });
});

describe("conversions", () => {
    test("what other tools count in", () => {
        expect(fromKiB(1)).toBe(1024);
        expect(fromMiB(1)).toBe(1048576);
        expect(inGB(2.5e9)).toBe(2.5);
        expect(inGB(fromMiB(6144))).toBeCloseTo(6.44, 2);
        expect(inGB("x")).toBe(0);
    });
    test("the mark's short form", () => {
        expect(compact(16.2e9)).toBe("16G");
        expect(compact(9.54e9)).toBe("9.5G");
        expect(compact(640e6)).toBe("640M");
        expect(compact(0)).toBe("1M");
    });
});

const ROOTS = ["shell", "shell-auth", "shell-saver", "greeter"];
const SOURCE = /\.(qml|mjs|js)$/;
const DIVIDES = /\/\s*(1024|1048576|1073741824|1099511627776|1e6|1e9|1e12|1000000|1000000000)\b/;
const SKIPPED = new Set(["assets", "node_modules"]);
const NOT_SIZES = ["shell/services/Spend.qml", "shell/services/spendreport.mjs"];

function files(dir) {
    const out = [];
    for (const name of readdirSync(dir)) {
        if (SKIPPED.has(name)) continue;
        const path = join(dir, name);
        if (statSync(path).isDirectory()) out.push(...files(path));
        else if (SOURCE.test(name)) out.push(path);
    }
    return out;
}

describe("one unit everywhere", () => {
    test("only sizes.mjs divides a size for display", () => {
        const base = new URL("../../", import.meta.url).pathname;
        const hits = [];
        for (const root of ROOTS) {
            let list = [];
            try { list = files(join(base, root)); } catch (e) { continue; }
            for (const f of list) {
                if (f.endsWith("shell/services/sizes.mjs") || NOT_SIZES.some(n => f.endsWith(n))) continue;
                readFileSync(f, "utf8").split("\n").forEach((line, i) => {
                    if (line.trim().startsWith("//")) return;
                    if (line.includes("$((") || line.includes("awk ")) return;
                    if (DIVIDES.test(line)) hits.push(f.slice(base.length) + ":" + (i + 1) + "  " + line.trim());
                });
            }
        }
        expect(hits).toEqual([]);
    });
    test("no size is labelled in binary units", () => {
        const base = new URL("../../", import.meta.url).pathname;
        const hits = [];
        for (const root of ROOTS) {
            let list = [];
            try { list = files(join(base, root)); } catch (e) { continue; }
            for (const f of list) {
                readFileSync(f, "utf8").split("\n").forEach((line, i) => {
                    if (line.trim().startsWith("//")) return;
                    if (/"[^"]*\b\d*\s?(GiB|MiB|KiB)\b[^"]*"/.test(line) && !/demuxer-max/.test(line)) hits.push(f.slice(base.length) + ":" + (i + 1));
                });
            }
        }
        expect(hits).toEqual([]);
    });
});
