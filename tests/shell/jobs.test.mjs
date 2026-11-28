import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { cleanupBusy, cleanupLabel, cleanupNote, cleanupPutBack, parse, running, storageNote, unseen } from "../../shell/services/jobs.mjs";

const done = (over) => parse(JSON.stringify({ id: "a1", kind: "storage", label: "pip", state: "done", code: 0, result: { ok: true, freed: 2.5e9 }, seen: false, ...over }));

describe("what the panel reads back from the job file", () => {
    test("no file, no job", () => {
        expect(parse("")).toEqual({ state: "none", id: "", label: "", code: -1, result: null, seen: false });
        expect(running(parse("not json"))).toBe(false);
        expect(unseen(parse("{}"))).toBe(false);
    });
    test("queued and running both mean still going, so the button stays on 'Clearing…'", () => {
        expect(running(done({ state: "queued" }))).toBe(true);
        expect(running(done({ state: "running" }))).toBe(true);
        expect(running(done())).toBe(false);
        expect(unseen(done({ state: "running" }))).toBe(false);
    });
    test("a finished run nobody has seen is shown once, then acknowledged", () => {
        expect(unseen(done())).toBe(true);
        expect(unseen(done({ seen: true }))).toBe(false);
        expect(unseen(done({ state: "lost" }))).toBe(true);
    });
});

describe("the words", () => {
    test("a cache cleared, a cache that wouldn't, a run that stopped", () => {
        expect(storageNote(done(), "Python packages (pip)")).toBe("Python packages (pip) cleared · 2.5 GB freed");
        expect(storageNote(done({ result: { ok: false, why: "pip's tool isn't installed" } }), "pip")).toBe("pip's tool isn't installed");
        expect(storageNote(done({ result: null, code: 1 }), "pip")).toBe("Couldn't clear pip");
        expect(storageNote(done({ state: "lost" }), "pip")).toBe("Clearing pip stopped before it finished");
    });
    test("cleanup says what moved, and what it was while it moved", () => {
        const l = cleanupLabel(false, "3 skills");
        const t = done({ label: l, result: { moved: ["a"], unlinked: ["b"] } });
        expect(cleanupBusy(t)).toBe("Moving 3 skills to the Trash…");
        expect(cleanupNote(t)).toBe("Moved 3 skills to the Trash; 1 linked from elsewhere: only the links went");
        expect(cleanupNote(done({ label: l, code: 1 }))).toBe("Couldn't move all of 3 skills");
        expect(cleanupPutBack(t)).toBe(true);
        expect(cleanupNote(done({ label: l, state: "lost" }))).toBe("Moving 3 skills stopped before it finished");
    });
    test("put back is its own kind of run, even for a skill called restore", () => {
        const back = done({ label: cleanupLabel(true, "") });
        expect(cleanupBusy(back)).toBe("Putting back…");
        expect(cleanupNote(back)).toBe("Put back");
        expect(cleanupNote(done({ label: cleanupLabel(true, ""), code: 1 }))).toBe("Nothing to put back");
        expect(cleanupPutBack(back)).toBe(false);
        expect(cleanupNote(done({ label: cleanupLabel(false, "restore") }))).toBe("Moved restore to the Trash");
    });
    test("nothing names a helper, an exit status or a path", () => {
        const all = [storageNote(done({ result: null, code: 3 }), "pip"), cleanupNote(done({ label: cleanupLabel(false, "x"), code: 7 })),
            cleanupNote(done({ state: "lost", label: cleanupLabel(false, "x") })), storageNote(done({ state: "lost" }), "pip")];
        for (const t of all) expect(t).not.toMatch(/kuwai-|exit|status|\/home|\/usr|code \d/i);
    });
});

describe("the panels use it", () => {
    const read = (p) => readFileSync(new URL("../../" + p, import.meta.url), "utf8");
    test("every deleting action goes through kuwai-job, none runs in the shell's own process tree", () => {
        for (const p of ["shell/modules/island/CachesView.qml", "shell/modules/island/CleanupPanel.qml", "shell/services/Sweep.qml"]) {
            const src = read(p);
            expect(src).toContain('"/kuwai-job", "start"');
            expect(src).toContain('"/kuwai-job", "status"');
            expect(src).not.toMatch(/execDetached\(\[bin, "--open"/);
        }
        expect(read("shell/modules/island/CachesView.qml")).not.toMatch(/command = \[Paths\.bin \+ "\/kuwai-storage", "clear"/);
        expect(read("shell/modules/island/CleanupPanel.qml")).not.toMatch(/id: actor/);
    });
    test("a panel that comes back asks for the job before it offers another", () => {
        expect(read("shell/modules/island/CachesView.qml")).toMatch(/watch\(\); \}/);
        expect(read("shell/modules/island/CleanupPanel.qml")).toMatch(/if \(acting\) return;/);
        expect(read("shell/services/Sweep.qml")).toMatch(/if \(reviewing\) return;/);
    });
});
