import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

import * as S from "../../shell/services/panelSchema.mjs";

const base = () => ({ kuwaiPanelSchema: 1, id: "demo", title: "Demo", state: "ready" });
const full = () => ({
    kuwaiPanelSchema: 1, id: "demo", title: "Demo", subtitle: "Something", state: "ready",
    hero: { value: "12 GB", label: "in 3 projects", detail: "idle 30+ days", tone: "neutral" },
    visualization: { type: "dotBar", total: 12, label: "Parts", buckets: [{ id: "a", label: "A", value: 8, tone: "info" }, { id: "b", label: "B", value: 4 }] },
    rowsLabel: "Rows",
    rows: [{ id: "r1", title: "One", detail: "d", meta: "m", badge: "new", actionId: "reviewProject" }],
    notice: { tone: "warn", title: "Old", detail: "From an hour ago", actionId: "refresh" },
    primaryAction: { id: "openUrl", label: "Docs", url: "https://example.com/docs" },
    footnote: "Nothing is deleted from here.",
});

describe("a payload is checked before it is drawn", () => {
    test("a full payload passes and comes back normalised", () => {
        const r = S.validate(full());
        expect(r.ok).toBe(true);
        if (!r.ok) return;
        expect(r.panel.rows[0].actionId).toBe("reviewProject");
        expect(r.panel.notice?.actionLabel).toBe("Scan now");
        expect(r.panel.visualization?.buckets[1].tone).toBe("neutral");
        expect(r.panel.primaryAction?.url).toBe("https://example.com/docs");
    });
    test("the smallest payload has every optional part empty", () => {
        const r = S.validate(base());
        expect(r).toEqual({ ok: true, panel: { kuwaiPanelSchema: 1, id: "demo", title: "Demo", subtitle: "", state: "ready", hero: null,
            visualization: null, rowsLabel: "", rows: [], notice: null, empty: null, primaryAction: null, footnote: "" } });
    });
    test("every state is accepted and nothing else", () => {
        for (const state of ["ready", "loading", "empty", "error", "stale", "not_installed", "busy"]) expect(S.validate({ ...base(), state }).ok).toBe(true);
        expect(S.validate({ ...base(), state: "exploded" })).toMatchObject({ ok: false, error: "bad_state" });
    });
    test("unknown fields are refused anywhere", () => {
        expect(S.validate({ ...base(), qml: "import Quickshell" })).toMatchObject({ ok: false, error: "unknown_field" });
        expect(S.validate({ ...base(), hero: { value: "1", command: ["rm"] } })).toMatchObject({ ok: false, where: "hero.command" });
        expect(S.validate({ ...base(), rows: [{ id: "a", title: "A", argv: ["sh"] }] })).toMatchObject({ ok: false, where: "rows[0].argv" });
    });
    test("tones, visualisations and intents come from closed lists", () => {
        expect(S.validate({ ...base(), notice: { title: "x", tone: "rainbow" } })).toMatchObject({ ok: false, error: "bad_tone" });
        expect(S.validate({ ...base(), visualization: { type: "pie", buckets: [{ id: "a", label: "A", value: 1 }] } })).toMatchObject({ ok: false, error: "bad_visualization" });
        expect(S.validate({ ...base(), notice: { title: "x", actionId: "runCommand" } })).toMatchObject({ ok: false, error: "unknown_intent" });
        expect(S.validate({ ...base(), primaryAction: { id: "exec", label: "Go" } })).toMatchObject({ ok: false, error: "unknown_intent" });
    });
    test("a link is opened only if Links.safeLink allows it", () => {
        expect(S.validate({ ...base(), primaryAction: { id: "openUrl", label: "Go", url: "file:///etc/passwd" } })).toMatchObject({ ok: false, error: "unsafe_url" });
        expect(S.validate({ ...base(), notice: { title: "x", actionId: "openUrl", url: "javascript:alert(1)" } })).toMatchObject({ ok: false, error: "unsafe_url" });
        expect(S.validate({ ...base(), rows: [{ id: "a", title: "A", actionId: "openUrl" }] })).toMatchObject({ ok: false, error: "unsafe_url" });
        expect(S.intentOf("openUrl", "https://ok.example")).toEqual({ intent: "openUrl", url: "https://ok.example" });
        expect(S.intentOf("openUrl", "ftp://x")).toBeNull();
        expect(S.intentOf("rm -rf", "")).toBeNull();
        expect(S.intentOf("refresh")).toEqual({ intent: "refresh", url: "" });
    });
    test("lists and strings are bounded", () => {
        const rows = Array.from({ length: 25 }, (_, i) => ({ id: "r" + i, title: "Row" }));
        expect(S.validate({ ...base(), rows })).toMatchObject({ ok: false, error: "too_many" });
        expect(S.validate({ ...base(), rows: rows.slice(0, 24) }).ok).toBe(true);
        const buckets = Array.from({ length: 9 }, (_, i) => ({ id: "b" + i, label: "B", value: 1 }));
        expect(S.validate({ ...base(), visualization: { type: "dotBar", buckets } })).toMatchObject({ ok: false, error: "too_many" });
        expect(S.validate({ ...base(), title: "x".repeat(121) })).toMatchObject({ ok: false, error: "too_long" });
        expect(S.validate({ ...base(), rows: [{ id: "a", title: "A\u202eevil" }] })).toMatchObject({ ok: false, error: "control_character" });
        expect(S.validate({ ...base(), rows: [{ id: "a", title: "A" }, { id: "a", title: "B" }] })).toMatchObject({ ok: false, error: "bad_id" });
    });
    test("numbers are finite and never negative; the total covers its parts", () => {
        const vis = (/** @type {any} */ value, total) => ({ ...base(), visualization: { type: "meter", total, buckets: [{ id: "a", label: "A", value }] } });
        expect(S.validate(vis(-1)).ok).toBe(false);
        expect(S.validate(vis(Infinity)).ok).toBe(false);
        expect(S.validate(vis("5")).ok).toBe(false);
        const r = S.validate(vis(10, 4));
        expect(r.ok && r.panel.visualization?.total).toBe(10);
    });
    test("a payload from another schema version is refused", () => {
        expect(S.validate({ ...base(), kuwaiPanelSchema: 2 })).toMatchObject({ ok: false, error: "schema_mismatch" });
        expect(S.validate({ ...base(), id: "../etc" })).toMatchObject({ ok: false, error: "bad_id" });
    });
});

describe("parse", () => {
    test("the byte cap is checked before JSON.parse ever runs", () => {
        const pad = "x".repeat(S.MAX_BYTES);
        expect(S.parse(JSON.stringify({ ...base(), footnote: pad }))).toMatchObject({ ok: false, error: "too_large" });
        const wide = "é".repeat(S.MAX_BYTES / 2 + 1);
        expect(wide.length).toBeLessThanOrEqual(S.MAX_BYTES);
        expect(S.parse(wide)).toMatchObject({ ok: false, error: "too_large" });
    });
    test("utf8Length counts like the encoder", () => {
        for (const s of ["", "abc", "é", "€", "😀", "a😀é", "\ud800"]) expect(S.utf8Length(s)).toBe(new TextEncoder().encode(s).length);
    });
    test("broken text and non-text are refused", () => {
        expect(S.parse("{not json")).toMatchObject({ ok: false, error: "unreadable" });
        expect(S.parse(42)).toMatchObject({ ok: false, error: "not_text" });
        expect(S.parse("[]")).toMatchObject({ ok: false, error: "not_object" });
        expect(S.parse(JSON.stringify(full())).ok).toBe(true);
    });
    test("the fallback for a broken payload is itself valid and says nothing internal", () => {
        const p = S.brokenPanel("demo", "Demo");
        expect(S.validate(p).ok).toBe(true);
        expect([p.notice?.title, p.notice?.detail, p.notice?.actionLabel].join(" ")).not.toMatch(/json|schema|exit|\/home|kuwai-/i);
    });
});

describe("cache paths stay inside their folder", () => {
    test("a panel's cache is under kuwai/panels/<id>", () => {
        expect(S.cacheDir("/home/a/.cache", "sweep")).toBe("/home/a/.cache/kuwai/panels/sweep");
        expect(S.cacheFile("/home/a/.cache/", "sweep", "snapshot.json")).toBe("/home/a/.cache/kuwai/panels/sweep/snapshot.json");
    });
    test("traversal, odd ids and relative homes are refused", () => {
        expect(S.cacheDir("/home/a/.cache", "../x")).toBe("");
        expect(S.cacheDir("/home/a/../b", "sweep")).toBe("");
        expect(S.cacheDir("relative", "sweep")).toBe("");
        expect(S.cacheFile("/c", "sweep", "../../etc/passwd")).toBe("");
        expect(S.cacheFile("/c", "sweep", "a/b")).toBe("");
        expect(S.cacheFile("/c", "sweep", "..json")).toBe("");
        expect(S.cacheFile("/c", "sweep", ".hidden")).toBe("");
    });
    test("only a small regular file with one link, owned by you, is read", () => {
        expect(S.statArgv("/c/x")).toEqual(["stat", "--format=%F|%s|%u|%h", "--", "/c/x"]);
        expect(S.cacheEntryOk("regular file|120|1000|1\n", 1000)).toBe(true);
        expect(S.cacheEntryOk("regular empty file|0|1000|1", 1000)).toBe(true);
        expect(S.cacheEntryOk("symbolic link|9|1000|1", 1000)).toBe(false);
        expect(S.cacheEntryOk("directory|4096|1000|2", 1000)).toBe(false);
        expect(S.cacheEntryOk("fifo|0|1000|1", 1000)).toBe(false);
        expect(S.cacheEntryOk("regular file|120|0|1", 1000)).toBe(false);
        expect(S.cacheEntryOk("regular file|120|1000|2", 1000)).toBe(false);
        expect(S.cacheEntryOk("regular file|70000|1000|1", 1000)).toBe(false);
        expect(S.cacheEntryOk("", 1000)).toBe(false);
    });
});

describe("a panel that keeps crashing is put aside", () => {
    test("two crashes quarantine it; a clean run before that resets the count", () => {
        let book = S.parseHealth("");
        book = S.noteCrash(book, "demo", 1);
        expect(S.allowed(book, "demo", {})).toBe(true);
        expect(S.allowed(S.noteHealthy(book, "demo"), "demo", {})).toBe(true);
        expect(S.noteHealthy(book, "demo").panels.demo.crashes).toBe(0);
        book = S.noteCrash(book, "demo", 2);
        expect(book.panels.demo).toEqual({ crashes: 2, quarantined: true, at: 2 });
        expect(S.allowed(book, "demo", {})).toBe(false);
        expect(S.allowed(S.noteHealthy(book, "demo"), "demo", {})).toBe(false);
        expect(S.allowed(S.release(book, "demo"), "demo", {})).toBe(true);
    });
    test("the file round-trips and a hand-edited one cannot smuggle ids", () => {
        const book = S.noteCrash(S.noteCrash(S.parseHealth(""), "demo", 5), "demo", 6);
        expect(S.parseHealth(S.healthText(book))).toEqual(book);
        const odd = S.parseHealth(JSON.stringify({ panels: { "../x": { crashes: 9 }, ok: { crashes: 1 }, bad: "no" } }));
        expect(Object.keys(odd.panels)).toEqual(["ok"]);
        expect(S.parseHealth("{broken")).toEqual({ version: 1, panels: {} });
        expect(S.healthPath("/home/a/.local/state")).toBe("/home/a/.local/state/kuwai/panel-health.json");
        expect(S.healthPath("nope")).toBe("");
    });
    test("KUWAI_NO_PLUGINS=1 turns every panel off", () => {
        expect(S.allowed(S.parseHealth(""), "demo", { KUWAI_NO_PLUGINS: "1" })).toBe(false);
        expect(S.allowed(S.parseHealth(""), "demo", { KUWAI_NO_PLUGINS: "0" })).toBe(true);
    });
});

describe("the module stays loadable by Qt", () => {
    test("no object spread and no Unicode property classes", () => {
        const src = readFileSync(new URL("../../shell/services/panelSchema.mjs", import.meta.url), "utf8");
        expect(src).not.toMatch(/\{\s*\.\.\.[A-Za-z_$]/);
        expect(src).not.toMatch(/\\[pP]\{/);
        expect(src).not.toMatch(/[\u2028\u2029]/);
    });
});
