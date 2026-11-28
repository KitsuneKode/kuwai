import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

import * as C from "../../shell/services/sweepContract.mjs";
import { validate, dotCounts, dotOwners } from "../../shell/services/panelSchema.mjs";

const NOW = Date.parse("2026-11-28T12:00:00Z");
const GB = 1e9;
const HOME = "/home/ada";
const iso = (ms) => new Date(ms).toISOString();
const read = (p) => readFileSync(new URL("../../" + p, import.meta.url), "utf8");

const widget = (over = {}) => ({
    widgetSchemaVersion: 1, protocolVersion: "1", readOnly: true, view: "projects", supportedViews: ["projects"],
    targetDir: HOME + "/Projects", generatedAt: iso(NOW - 10 * 60000), source: "cache", stale: false, partial: false, skippedDirs: 0,
    projectsSummary: {
        reclaimableBytes: 61633196850, safeBytes: 61203280690, cautionBytes: 429916160, guardedBytes: 4509715660, protectedCount: 22,
        projectCount: 112, idle: { days: 30, projects: 26, bytes: 7301444403 },
        byCost: [
            { cost: "cache", label: "Caches", bytes: 2254857830, count: 41, hint: "Comes back on its own" },
            { cost: "install", label: "Installs", bytes: 41446431129, count: 96, hint: "Reinstalls from lockfile" },
            { cost: "build", label: "Builds", bytes: 17501991731, count: 48, hint: "Rebuilds on next compile" },
            { cost: "custom", label: "Opt-in", bytes: 429916160, count: 6, hint: "Check first" },
        ],
        topProjects: [
            { name: "old-renderer", repo: "sweep", path: HOME + "/Projects/sweep/.worktrees/old-renderer", bytes: 1288490188, idleDays: 42, worktreeState: "merged" },
            { name: "blog", repo: "", path: HOME + "/Projects/blog", bytes: 900000000, idleDays: 400 },
        ],
    },
    suggestion: null, receipt: null, space: null, error: null, ...over,
});

const legacy = (over = {}) => ({
    alive: true, checkedAt: Math.round((NOW - 45 * 60000) / 1000), stale: false, root: HOME + "/Projects",
    reclaimable: 36 * GB, safe: 29 * GB, caution: 7 * GB, protected: 12,
    idle: { days: 30, projects: 2, bytes: 31.8 * GB, kinds: [{ kind: "node_modules", bytes: 22 * GB, count: 19 }, { kind: "target", bytes: 9.8 * GB, count: 4 }] },
    kinds: [{ kind: "node_modules", bytes: 26 * GB, count: 30 }],
    projects: [{ name: "old-shop", path: HOME + "/Projects/old-shop", bytes: 9.4 * GB, idleDays: 212 },
        { name: "sweep-ui", path: HOME + "/Projects/kuwai/.worktrees/sweep-ui", bytes: 6.3 * GB, idleDays: 44 }],
    ...over,
});

const ctx = (over = {}) => ({ nowMs: NOW, onBattery: false, scanning: false, installed: true, apply: null, receipt: null, copied: false,
    reviewing: false, markOff: false, ...over });

const panelOf = (data, c = {}) => {
    const p = C.toPanel(C.summarize(data, HOME + "/Projects"), ctx(c));
    const r = validate(p);
    expect(r.ok ? "" : r.error + " at " + r.where).toBe("");
    return r.ok ? r.panel : p;
};

const words = (p) => [p.title, p.subtitle, p.footnote, p.hero && [p.hero.value, p.hero.label, p.hero.detail], p.notice && [p.notice.title, p.notice.detail, p.notice.actionLabel],
    p.empty && [p.empty.title, p.empty.detail, p.empty.actionLabel], p.primaryAction && p.primaryAction.label, p.visualization && p.visualization.buckets.map(b => [b.label, b.detail]),
    p.rows.map(r => [r.title, r.detail, r.meta, r.badge])].flat(4).filter(Boolean).join("\n");

const INSIDES = /\/home|\/usr|kuwai-|kitty|SIGTERM|SIGKILL|exit (code|status|\d)|\bGiB\b|\bMiB\b|stderr|setpriv|\.json/i;

const STATES = {
    ready: () => panelOf(widget()),
    "ready-legacy": () => panelOf(legacy()),
    scanning: () => panelOf({ alive: true, pending: true, refreshing: true, root: HOME + "/Projects", checkedAt: 0 }),
    "stale-battery": () => panelOf(widget({ generatedAt: iso(NOW - 3 * 3600000) }), { onBattery: true }),
    "missing-battery": () => panelOf(null, { onBattery: true }),
    "active-apply": () => panelOf(widget(), { apply: C.activeApply({ applyVersion: 1, pid: 48210, updatedAt: iso(NOW - 2000), mode: "delete", selectedCount: 12, deletedCount: 3, estimatedBytesFreed: 1932735283 }, NOW) }),
    "receipt-delete": () => panelOf(widget(), { receipt: C.receipt({ id: "r1", completedAt: iso(NOW - 60000), mode: "delete", deletedCount: 5, failedCount: 0, totalBytesFreed: 3758096384 }, NOW, "") }),
    "receipt-trash": () => panelOf(widget(), { receipt: C.receipt({ id: "r2", completedAt: iso(NOW - 60000), mode: "trash", deletedCount: 5, failedCount: 0, totalBytesFreed: 0, totalBytesMoved: 3758096384 }, NOW, "") }),
    "receipt-partial": () => panelOf(widget(), { receipt: C.receipt({ id: "r3", completedAt: iso(NOW - 60000), mode: "delete", deletedCount: 3, failedCount: 2, totalBytesFreed: 3.1 * GB }, NOW, "") }),
    empty: () => panelOf(widget({ projectsSummary: { reclaimableBytes: 0, protectedCount: 0, idle: { days: 30, projects: 0, bytes: 0 }, byCost: [], topProjects: [] } })),
    "not-installed": () => panelOf(null, { installed: false }),
    "not-installed-legacy": () => panelOf({ alive: false }),
    error: () => panelOf(widget({ projectsSummary: null, generatedAt: null, error: { code: "permission_denied", message: "x", retryable: false } })),
    "error-legacy": () => panelOf({ alive: true, root: HOME + "/Projects", checkedAt: 0, error: "scan failed (exit 3)" }),
    "schema-mismatch": () => panelOf({ widgetSchemaVersion: 2, targetDir: HOME + "/Projects" }),
};

describe("every state is a valid panel that names nothing internal", () => {
    for (const [name, make] of Object.entries(STATES)) {
        test(name, () => {
            const p = make();
            expect(words(p)).not.toMatch(INSIDES);
            if (p.state !== "loading") expect(words(p).length).toBeGreaterThan(0);
        });
    }
    test("each state lands where it should", () => {
        const s = Object.fromEntries(Object.entries(STATES).map(([k, f]) => [k, f().state]));
        expect(s).toEqual({ ready: "ready", "ready-legacy": "ready", scanning: "loading", "stale-battery": "stale", "missing-battery": "stale",
            "active-apply": "busy", "receipt-delete": "ready", "receipt-trash": "ready", "receipt-partial": "ready", empty: "empty",
            "not-installed": "not_installed", "not-installed-legacy": "not_installed", error: "error", "error-legacy": "error", "schema-mismatch": "error" });
    });
});

describe("sizes are decimal, through Sizes.bytes", () => {
    test("the upstream snapshot's binary bytes print as GB, never GiB", () => {
        const p = STATES.ready();
        expect(p.hero?.value).toBe("7.3 GB");
        expect(p.hero?.detail).toContain("62 GB across all projects");
        expect(p.visualization?.buckets.map(b => b.label)).toEqual(["Installs", "Builds", "Caches", "Opt-in"]);
        expect(p.visualization?.buckets[0].detail).toBe("41 GB · 96 folders · Reinstalls from lockfile");
        expect(p.rows[0]).toMatchObject({ title: "sweep › old-renderer", meta: "42 days · 1.3 GB", actionId: "reviewProject" });
    });
    test("the legacy answer reads the same way", () => {
        const p = STATES["ready-legacy"]();
        expect(p.hero?.value).toBe("32 GB");
        expect(p.rows.map(r => r.title)).toEqual(["old-shop", "kuwai › sweep-ui"]);
        expect(p.rows[0].meta).toBe("7 months · 9.4 GB");
        expect(p.visualization?.label).toBe("What the idle projects hold");
    });
    test("buckets past eight fold into Everything else", () => {
        const byCost = Array.from({ length: 10 }, (_, i) => ({ cost: "custom", bytes: (10 - i) * GB }));
        const s = C.summarize(widget({ projectsSummary: { ...widget().projectsSummary, byCost } }));
        const p = C.toPanel(s, ctx());
        expect(p.visualization.buckets.length).toBe(8);
        expect(p.visualization.buckets[7]).toMatchObject({ id: "rest", label: "Everything else", value: 6 * GB, tone: "muted" });
    });
});

describe("receipts tell the truth about the Trash", () => {
    test("trash never claims to have freed anything", () => {
        const n = STATES["receipt-trash"]().notice;
        expect(n?.title).toBe("Moved 3.8 GB to the Trash");
        expect(words(STATES["receipt-trash"]())).not.toMatch(/freed/i);
        expect(n?.detail).toContain("empty it");
    });
    test("delete says what it freed; a partial run is amber and says what stayed", () => {
        expect(STATES["receipt-delete"]().notice).toMatchObject({ tone: "good", title: "Freed 3.8 GB" });
        expect(STATES["receipt-partial"]().notice).toMatchObject({ tone: "warn", title: "Freed 3.1 GB · 2 items stayed", actionId: "reviewProject" });
    });
    test("a trash receipt without a size counts items instead", () => {
        const r = C.receipt({ id: "x", completedAt: iso(NOW), mode: "trash", deletedCount: 1 }, NOW, "");
        expect(C.receiptNotice(r).title).toBe("Moved 1 item to the Trash");
    });
    test("a receipt expires after a day, once dismissed, or from another version", () => {
        const r = { id: "r1", completedAt: iso(NOW - 25 * 3600000), mode: "delete", deletedCount: 1 };
        expect(C.receipt(r, NOW, "")).toBeNull();
        expect(C.receipt({ ...r, completedAt: iso(NOW - 3600000) }, NOW, "r1")).toBeNull();
        expect(C.receipt({ ...r, completedAt: iso(NOW - 3600000) }, NOW, "")).not.toBeNull();
        expect(C.receipt({ ...r, completedAt: iso(NOW - 3600000), receiptVersion: 2 }, NOW, "")).toBeNull();
        expect(C.receipt({ ...r, id: "" }, NOW, "")).toBeNull();
        expect(C.parseDismissed(C.dismissedText("r9"))).toBe("r9");
        expect(C.parseDismissed("garbage")).toBe("");
    });
});

describe("a clear in progress is believed only while it is alive", () => {
    const a = { applyVersion: 1, pid: 4242, updatedAt: iso(NOW - 1000), selectedCount: 12, deletedCount: 3, estimatedBytesFreed: 2e9 };
    test("fresh and well formed", () => {
        expect(C.activeApply(a, NOW)).toMatchObject({ done: 3, total: 12, mode: "delete" });
        expect(STATES["active-apply"]().hero?.value).toBe("Clearing 3 of 12");
        expect(STATES["active-apply"]().visualization?.type).toBe("meter");
    });
    test("30 seconds without an update, a bad pid, another boot or another version is a leftover", () => {
        expect(C.activeApply({ ...a, updatedAt: iso(NOW - 30000) }, NOW)).toBeNull();
        expect(C.activeApply({ ...a, updatedAt: iso(NOW + 60000) }, NOW)).toBeNull();
        expect(C.activeApply({ ...a, pid: 1 }, NOW)).toBeNull();
        expect(C.activeApply({ ...a, pid: "4242" }, NOW)).toBeNull();
        expect(C.activeApply({ ...a, bootId: "old" }, NOW, "new")).toBeNull();
        expect(C.activeApply({ ...a, bootId: "same" }, NOW, "same")).not.toBeNull();
        expect(C.activeApply({ ...a, startTicks: -4 }, NOW)).toBeNull();
        expect(C.activeApply({ ...a, applyVersion: 2 }, NOW)).toBeNull();
        expect(C.activeApply(null, NOW)).toBeNull();
    });
    test("trash mode says moved, not freed", () => {
        const p = panelOf(widget(), { apply: C.activeApply({ ...a, mode: "trash" }, NOW) });
        expect(p.hero?.label).toBe("About 2 GB moved to the Trash so far");
    });
});

describe("when to count", () => {
    test("the bands are 30 and 60 minutes", () => {
        expect(C.band(0, NOW)).toBe("missing");
        expect(C.band(NOW - 29 * 60000, NOW)).toBe("fresh");
        expect(C.band(NOW - 30 * 60000, NOW)).toBe("quiet");
        expect(C.band(NOW - 59 * 60000, NOW)).toBe("quiet");
        expect(C.band(NOW - 60 * 60000, NOW)).toBe("stale");
    });
    const plan = (o) => C.plan({ band: "stale", onBattery: false, deliberate: true, installed: true, ...o });
    test("a deliberate open on AC counts what is old or missing, quietly in the middle band", () => {
        expect(plan({ band: "fresh" })).toBe("none");
        expect(plan({ band: "quiet" })).toBe("scan");
        expect(plan({ band: "stale" })).toBe("scan");
        expect(plan({ band: "missing" })).toBe("scan");
    });
    test("on battery nothing counts on its own, not even a first count", () => {
        expect(plan({ onBattery: true, band: "quiet" })).toBe("none");
        expect(plan({ onBattery: true, band: "stale" })).toBe("ask");
        expect(plan({ onBattery: true, band: "missing" })).toBe("ask");
        expect(plan({ onBattery: true, manual: true })).toBe("scan");
    });
    test("a hover never counts; nothing runs twice or without Sweep", () => {
        expect(plan({ deliberate: false })).toBe("none");
        expect(plan({ deliberate: false, band: "missing" })).toBe("none");
        expect(plan({ scanning: true, manual: true })).toBe("none");
        expect(plan({ installed: false, manual: true })).toBe("none");
        expect(plan({ installed: null })).toBe("none");
    });
    test("the battery prompt and the stale notice offer one action", () => {
        expect(STATES["missing-battery"]().notice).toMatchObject({ actionId: "refresh", actionLabel: "Count now" });
        expect(STATES["stale-battery"]().notice).toMatchObject({ tone: "warn", actionId: "refresh", title: "Counted 3 h ago" });
    });
});

describe("the binary and the commands", () => {
    test("only the fixed places are trusted, written canonically", () => {
        expect(C.candidates(HOME)).toEqual([HOME + "/.local/bin/sweep", HOME + "/.bun/bin/sweep", HOME + "/.linuxbrew/bin/sweep",
            "/home/linuxbrew/.linuxbrew/bin/sweep", "/usr/local/bin/sweep", "/usr/bin/sweep"]);
        expect(C.validBinary("/usr/bin/sweep", HOME)).toBe(true);
        expect(C.validBinary(HOME + "/.bun/bin/sweep", HOME)).toBe(true);
        for (const bad of ["/tmp/sweep", "/usr/bin/../bin/sweep", "/usr//bin/sweep", "usr/bin/sweep", "/usr/bin/sweep/", "/usr/bin/sweep\n", HOME + "/./.bun/bin/sweep"])
            expect(C.validBinary(bad, HOME)).toBe(false);
        expect(C.candidates("/home/../root")).toEqual(["/home/linuxbrew/.linuxbrew/bin/sweep", "/usr/local/bin/sweep", "/usr/bin/sweep"]);
        expect(C.probed("/tmp/evil\n", HOME)).toBe("");
        expect(C.probed("/usr/bin/sweep\n", HOME)).toBe("/usr/bin/sweep");
    });
    test("the probe passes paths as arguments to a fixed script", () => {
        const argv = C.probeArgv(HOME);
        expect(argv.slice(0, 4)).toEqual(["sh", "-c", C.PROBE, "sh"]);
        expect(C.PROBE).not.toContain(HOME);
    });
    test("counting is read-only, low priority and dies with the shell", () => {
        const argv = C.widgetArgv("/usr/bin/sweep", HOME + "/Projects", false);
        expect(argv.slice(0, 4)).toEqual(["setpriv", "--pdeathsig", "KILL", "--"]);
        expect(argv).toContain("ionice");
        expect(argv.slice(argv.indexOf("/usr/bin/sweep"))).toEqual(["/usr/bin/sweep", "widget", HOME + "/Projects", "--view", "projects", "--json", "--refresh", "--resource-profile", "low-memory"]);
        expect(C.widgetArgv("/usr/bin/sweep", "/p", true)).toContain("--cache-only");
        expect(argv.join(" ")).not.toMatch(/\b(apply|delete|rm|trash)\b/);
    });
    test("review opens sweep ui in a terminal as plain arguments", () => {
        expect(C.reviewArgv("/k/bin/kuwai-term", "/usr/bin/sweep", "/p/a b")).toEqual(["/k/bin/kuwai-term", "--title", "sweep", "--dir", "/p/a b", "--wait", "--hold", "--", "/usr/bin/sweep", "ui", "/p/a b"]);
        const s = C.summarize(legacy());
        expect(C.reviewDir(s, "p1", HOME)).toBe(HOME + "/Projects/kuwai/.worktrees/sweep-ui");
        expect(C.reviewDir(s, "", HOME)).toBe(HOME + "/Projects");
        expect(C.reviewDir(s, "p99", HOME)).toBe(HOME + "/Projects");
        expect(C.reviewDir(C.summarize({ alive: true, projects: [{ path: "/p/../etc" }] }), "p0", HOME)).toBe("");
    });
    test("the install line is the published one and the button checks only after the copy worked", () => {
        expect(C.INSTALL_COMMAND).toBe("curl -fsSL https://raw.githubusercontent.com/KitsuneKode/sweep/main/install.sh | sh");
        expect(STATES["not-installed"]().empty?.actionLabel).toBe("Copy install command");
        expect(panelOf(null, { installed: false, copied: true }).empty?.actionLabel).toBe("Copied ✓");
        expect(STATES["not-installed"]().primaryAction).toMatchObject({ id: "openUrl", url: C.HELP_URL });
    });
});

describe("the dot bar is proportional", () => {
    test("parts get their share of the cells and every part shows", () => {
        expect(dotCounts([50, 30, 20], 100, 10)).toEqual([5, 3, 2]);
        expect(dotCounts([1, 1000], 0, 20)).toEqual([1, 19]);
        expect(dotCounts([1, 1, 1], 3, 2).reduce((a, b) => a + b, 0)).toBe(2);
        expect(dotCounts([25], 100, 8)).toEqual([2]);
        expect(dotCounts([0, -1, NaN], 10, 8)).toEqual([0, 0, 0]);
        const big = [41446431129, 17501991731, 2254857830, 429916160];
        const c = dotCounts(big, big.reduce((a, b) => a + b), 6 * 60);
        expect(c.reduce((a, b) => a + b)).toBe(360);
        expect(c.every(n => n > 0)).toBe(true);
        expect(dotOwners([2, 1], 4)).toEqual([0, 0, 1, -1]);
    });
});

describe("the shell keeps its promises", () => {
    const sweep = read("shell/services/Sweep.qml");
    const panel = read("shell/modules/island/SweepPanel.qml");
    test("no timer spawns anything while the panel is closed", () => {
        const timers = sweep.match(/Timer \{[^}]*\}/g) || [];
        for (const t of timers) expect(t).not.toMatch(/running:\s*root\.enabled|running = true|\.running = true|check\(/);
        expect(sweep).toMatch(/running: root\.shown/);
        expect(sweep).not.toMatch(/interval: 300000|interval: 45000/);
    });
    test("caches and live state are watched, not polled", () => {
        for (const f of ["/sweep/widget-v1.json", "/active-apply.json", "/sweep/last-receipt.json", "/sweep-status.json"]) expect(sweep).toContain(f);
        expect(sweep).toContain('["mkdir", "-p", "-m", "0700", "--", root.runtimeDir]');
    });
    test("compatibility: IPC, the viewed mark and the settings keys", () => {
        expect(sweep).toMatch(/IpcHandler \{\s*target: "sweep"/);
        expect(sweep).toMatch(/function open\(\): void/);
        expect(sweep).toMatch(/function refresh\(\): void/);
        expect(sweep).toContain('"/sweep-viewed"');
        expect(sweep).toContain("Settings.sweepMark");
        expect(sweep).toContain("Settings.sweepMinGB");
        for (const p of ["fresh", "compact", "tip", "markViewed"]) expect(sweep).toMatch(new RegExp("\\b" + p + "\\b"));
    });
    test("nothing in Kuwai deletes; review goes through kuwai-job and kuwai-term", () => {
        expect(sweep + panel).not.toMatch(/"(apply|delete|rm|trash)"|execDetached/);
        expect(sweep).toContain('"/kuwai-job", "start", "sweep", "review"');
        expect(sweep).toContain('"/kuwai-term"');
        expect(panel).toContain("Ui.DeclarativePanel");
        expect(panel).not.toMatch(/Process|execDetached|Quickshell\.Io/);
    });
    test("hover is cache-only: only a deliberate open may count", () => {
        expect(panel).toContain("Sweep.opened(!Island.previewing)");
        expect(sweep).toMatch(/deliberate: deliberate && shown/);
    });
});

describe("the rehearsal scenes still stage", () => {
    const doc = JSON.parse(read("tests/ui/scenes.json"));
    const scenes = doc.scenes.filter(s => s.panel === "SweepPanel");
    const sweep = read("shell/services/Sweep.qml");
    test("there is a scene for the states that matter", () => {
        const ids = scenes.map(s => s.id);
        for (const id of ["sweep/typical", "sweep/counting", "sweep/failed", "sweep/worst", "sweep/not-installed", "sweep/stale-battery", "sweep/receipt-trash", "sweep/empty"])
            expect(ids).toContain(id);
    });
    for (const s of scenes) {
        test(s.id, () => {
            const nowS = Math.round(NOW / 1000);
            const fill = (v) => typeof v === "string" && /^@now-\d+s$/.test(v) ? nowS - Number(v.slice(5, -1)) :
                typeof v === "string" && /^@now-\d+iso$/.test(v) ? iso(NOW - Number(v.slice(5, -3)) * 1000) :
                Array.isArray(v) ? v.map(fill) : v && typeof v === "object" ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, fill(x)])) : v;
            const set = Object.fromEntries((s.set || []).filter(x => x[0] === "Sweep").map(x => [x[1], fill(x[2])]));
            for (const k of Object.keys(set)) expect(sweep).toMatch(new RegExp("property (var|bool|string|real|int) " + k + "\\b"));
            const c = ctx({ installed: set.installed === undefined ? null : set.installed, onBattery: !!set.onBattery,
                receipt: C.receipt(set.receiptRaw, NOW, ""), apply: C.activeApply(set.applyRaw, NOW) });
            const p = panelOf(set.data === undefined ? null : set.data, c);
            expect(words(p)).not.toMatch(INSIDES);
        });
    }
});
