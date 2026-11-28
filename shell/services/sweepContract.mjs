// @ts-check
import { bytes } from "./sizes.mjs";
import { SCHEMA, MAX_ROWS, MAX_BUCKETS } from "./panelSchema.mjs";

export const INSTALL_COMMAND = "curl -fsSL https://raw.githubusercontent.com/KitsuneKode/sweep/main/install.sh | sh";
export const HELP_URL = "https://github.com/KitsuneKode/sweep";
export const QUIET_MS = 30 * 60000;
export const STALE_MS = 60 * 60000;
export const APPLY_LIVE_MS = 30000;
export const RECEIPT_MS = 24 * 3600000;
export const SAFETY = "Nothing is deleted from here. Sweep asks before it removes anything.";

const ERRORS = ["not_installed", "engine_missing", "permission_denied", "target_missing", "timeout", "scan_failed", "schema_mismatch"];
const COSTS = { cache: "Caches", install: "Installs", build: "Builds", custom: "Opt-in" };
const CONTROLS = /[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069]/g;
const CONTROL = /[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069]/;

/** @param {unknown} home */
export function candidates(home) {
    const h = String(home || "").replace(/\/+$/, "");
    const mine = h.startsWith("/") && !/(^|\/)\.\.?(\/|$)/.test(h) ? [h + "/.local/bin/sweep", h + "/.bun/bin/sweep", h + "/.linuxbrew/bin/sweep"] : [];
    return mine.concat(["/home/linuxbrew/.linuxbrew/bin/sweep", "/usr/local/bin/sweep", "/usr/bin/sweep"]);
}

/**
 * @param {unknown} path
 * @param {unknown} home
 */
export function validBinary(path, home) {
    if (typeof path !== "string" || !path.startsWith("/") || /[\u0000-\u001f]/.test(path)) return false;
    if (/\/\/|\/\.\.?(\/|$)/.test(path) || path.endsWith("/")) return false;
    return candidates(home).indexOf(path) >= 0;
}

export const PROBE = 'for p do if [ -f "$p" ] && [ -x "$p" ]; then printf "%s\\n" "$p"; exit 0; fi; done; exit 1';

/** @param {unknown} home */
export function probeArgv(home) {
    return ["sh", "-c", PROBE, "sh"].concat(candidates(home));
}

/**
 * @param {unknown} out
 * @param {unknown} home
 */
export function probed(out, home) {
    const p = String(out || "").split("\n")[0].trim();
    return validBinary(p, home) ? p : "";
}

/**
 * @param {string} exe
 * @param {string} root
 * @param {boolean} cacheOnly
 */
export function widgetArgv(exe, root, cacheOnly) {
    return ["setpriv", "--pdeathsig", "KILL", "--", "nice", "-n", "19", "ionice", "-c3", exe, "widget", root, "--view", "projects", "--json",
        cacheOnly ? "--cache-only" : "--refresh", "--resource-profile", "low-memory"];
}

/**
 * @param {string} term
 * @param {string} exe
 * @param {string} dir
 */
export function reviewArgv(term, exe, dir) {
    return [term, "--title", "sweep", "--dir", dir, "--wait", "--hold", "--", exe, "ui", dir];
}

/**
 * @param {unknown} v
 * @returns {number}
 */
export function when(v) {
    if (typeof v === "number" && isFinite(v) && v > 0) return v < 1e11 ? v * 1000 : v;
    if (typeof v === "string" && v.length <= 40) {
        const t = Date.parse(v);
        return isFinite(t) && t > 0 ? t : 0;
    }
    return 0;
}

/**
 * @param {number} checkedAtMs
 * @param {number} nowMs
 * @returns {"missing"|"fresh"|"quiet"|"stale"}
 */
export function band(checkedAtMs, nowMs) {
    if (!(checkedAtMs > 0)) return "missing";
    const age = nowMs - checkedAtMs;
    if (age < QUIET_MS) return "fresh";
    return age < STALE_MS ? "quiet" : "stale";
}

/**
 * @param {{ band: string, onBattery: boolean, deliberate: boolean, manual?: boolean, scanning?: boolean, installed: boolean | null }} s
 * @returns {"none"|"scan"|"ask"}
 */
export function plan(s) {
    if (s.installed !== true || s.scanning) return "none";
    if (s.manual) return "scan";
    if (!s.deliberate || s.band === "fresh") return "none";
    if (s.onBattery) return s.band === "quiet" ? "none" : "ask";
    return "scan";
}

/** @param {unknown} v */
function num(v) {
    const n = Number(v);
    return isFinite(n) && n > 0 ? n : 0;
}

/**
 * @param {unknown} v
 * @param {number} max
 */
function str(v, max) {
    return typeof v === "string" ? v.replace(CONTROLS, " ").slice(0, max) : "";
}

/** @param {unknown} v */
function isObj(v) { return !!v && typeof v === "object" && !Array.isArray(v); }

/** @param {unknown} why */
function legacyError(why) {
    const w = String(why || "");
    if (!w) return "";
    if (/sweep not found/.test(w)) return "not_installed";
    if (/folder missing/.test(w)) return "target_missing";
    if (/timed out/.test(w)) return "timeout";
    return "scan_failed";
}

/**
 * @typedef {{ id: string, label: string, bytes: number, count: number, hint: string }} Part
 * @typedef {{ name: string, repo: string, path: string, bytes: number, idleDays: number }} Project
 * @typedef {{ source: string, installed: boolean | null, pending: boolean, refreshing: boolean, error: string, checkedAt: number,
 *   root: string, idleBytes: number, idleProjects: number, idleDays: number, reclaimable: number, protectedCount: number,
 *   parts: Part[], projects: Project[], partial: boolean }} Summary
 */

/** @returns {Summary} */
function blank() {
    return { source: "none", installed: null, pending: false, refreshing: false, error: "", checkedAt: 0, root: "", idleBytes: 0,
        idleProjects: 0, idleDays: 30, reclaimable: 0, protectedCount: 0, parts: [], projects: [], partial: false };
}

/**
 * @param {unknown} path
 * @param {unknown} name
 */
export function where(path, name) {
    const p = String(path || "").replace(/\/+$/, "");
    const m = /\/([^/]+)\/(?:\.worktrees|\.claude\/worktrees)\/([^/]+)$/.exec(p);
    if (m) return { repo: m[1], name: m[2] };
    return { repo: "", name: String(name || p.slice(p.lastIndexOf("/") + 1) || p) };
}

/**
 * @param {any} d
 * @returns {Summary}
 */
function fromLegacy(d) {
    const s = blank();
    s.source = "legacy";
    if (d.alive === false) { s.installed = false; return s; }
    if (d.alive === true) s.installed = true;
    s.pending = d.pending === true;
    s.refreshing = d.refreshing === true;
    s.error = legacyError(d.error);
    s.checkedAt = when(d.checkedAt);
    s.root = str(d.root, 4096);
    const idle = isObj(d.idle) ? d.idle : {};
    s.idleBytes = num(idle.bytes);
    s.idleProjects = Math.round(num(idle.projects));
    s.idleDays = Math.round(num(idle.days)) || 30;
    s.reclaimable = num(d.reclaimable);
    s.protectedCount = Math.round(num(d.protected));
    const kinds = Array.isArray(idle.kinds) && idle.kinds.length && s.idleBytes > 0 ? idle.kinds : Array.isArray(d.kinds) ? d.kinds : [];
    s.parts = kinds.filter(isObj).map((/** @type {any} */ k) => ({ id: str(k.kind, 64), label: str(k.kind, 64), bytes: num(k.bytes), count: Math.round(num(k.count)), hint: "" }))
        .filter((/** @type {Part} */ k) => k.id && k.bytes > 0);
    s.projects = (Array.isArray(d.projects) ? d.projects : []).filter(isObj).map((/** @type {any} */ p) => {
        const at = where(p.path, p.name);
        return { name: str(at.name, 120), repo: str(at.repo, 120), path: str(p.path, 4096), bytes: num(p.bytes), idleDays: Math.round(num(p.idleDays)) };
    });
    return s;
}

/**
 * @param {any} d
 * @param {string} root
 */
export function snapshotOf(d, root) {
    if (!isObj(d)) return null;
    if (isObj(d.entries)) {
        if (d.cacheVersion !== 1) return { widgetSchemaVersion: -1 };
        const keys = Object.keys(d.entries);
        const key = root && d.entries[root] ? root : keys.length === 1 ? keys[0] : "";
        return key && isObj(d.entries[key]) ? d.entries[key] : null;
    }
    if (d.type === "widget_snapshot" && isObj(d.snapshot)) return d.snapshot;
    return d;
}

/**
 * @param {any} d
 * @returns {Summary}
 */
function fromWidget(d) {
    const s = blank();
    s.source = "widget";
    s.installed = true;
    if (d.widgetSchemaVersion !== 1) { s.error = "schema_mismatch"; return s; }
    s.root = str(d.targetDir, 4096);
    s.checkedAt = when(d.generatedAt);
    s.partial = d.partial === true;
    if (isObj(d.error)) s.error = ERRORS.indexOf(d.error.code) >= 0 ? d.error.code : "scan_failed";
    const ps = isObj(d.projectsSummary) ? d.projectsSummary : null;
    if (!ps) { s.pending = !s.error && !s.checkedAt; return s; }
    const idle = isObj(ps.idle) ? ps.idle : {};
    s.idleBytes = num(idle.bytes);
    s.idleProjects = Math.round(num(idle.projects));
    s.idleDays = Math.round(num(idle.days)) || 30;
    s.reclaimable = num(ps.reclaimableBytes);
    s.protectedCount = Math.round(num(ps.protectedCount));
    s.parts = (Array.isArray(ps.byCost) ? ps.byCost : []).filter(isObj).map((/** @type {any} */ c) => {
        const id = Object.prototype.hasOwnProperty.call(COSTS, c.cost) ? c.cost : "custom";
        return { id, label: COSTS[/** @type {keyof typeof COSTS} */ (id)], bytes: num(c.bytes), count: Math.round(num(c.count)), hint: str(c.hint, 80) };
    }).filter((/** @type {Part} */ c) => c.bytes > 0);
    s.projects = (Array.isArray(ps.topProjects) ? ps.topProjects : []).filter(isObj).map((/** @type {any} */ p) => {
        const at = where(p.path, p.name);
        return { name: str(p.name, 120) || str(at.name, 120), repo: str(p.repo, 120) || str(at.repo, 120), path: str(p.path, 4096),
            bytes: num(p.bytes), idleDays: Math.round(num(p.idleDays)) };
    });
    return s;
}

/**
 * @param {unknown} data
 * @param {string} [root]
 * @returns {Summary}
 */
export function summarize(data, root) {
    if (!isObj(data)) return blank();
    const d = /** @type {any} */ (data);
    if ("widgetSchemaVersion" in d || "entries" in d || d.type === "widget_snapshot") {
        const snap = snapshotOf(d, root || "");
        return snap ? fromWidget(snap) : blank();
    }
    return fromLegacy(d);
}

/** @param {Summary} s */
export function counted(s) {
    return s.checkedAt > 0 && !s.pending;
}

/**
 * @param {unknown} raw
 * @param {number} nowMs
 * @param {string} [bootId]
 */
export function activeApply(raw, nowMs, bootId) {
    if (!isObj(raw)) return null;
    const a = /** @type {any} */ (raw);
    if (a.applyVersion !== undefined && a.applyVersion !== 1) return null;
    if (!Number.isInteger(a.pid) || a.pid <= 1) return null;
    const at = when(a.updatedAt);
    if (!at || nowMs - at >= APPLY_LIVE_MS || at - nowMs > 5000) return null;
    if (a.bootId !== undefined && (typeof a.bootId !== "string" || (bootId && a.bootId !== bootId))) return null;
    if (a.startTicks !== undefined && !(Number.isInteger(a.startTicks) && a.startTicks > 0)) return null;
    const total = Math.round(num(a.selectedCount));
    return { pid: a.pid, mode: a.mode === "trash" ? "trash" : "delete", done: Math.min(total || Infinity, Math.round(num(a.deletedCount))),
        total, failed: Math.round(num(a.failedCount)), bytes: num(a.estimatedBytesFreed), until: at + APPLY_LIVE_MS };
}

/**
 * @param {unknown} raw
 * @param {number} nowMs
 * @param {string} dismissedId
 */
export function receipt(raw, nowMs, dismissedId) {
    if (!isObj(raw)) return null;
    const r = /** @type {any} */ (raw);
    if (r.receiptVersion !== undefined && r.receiptVersion !== 1) return null;
    const id = str(r.id, 64);
    if (!id || id === dismissedId) return null;
    const at = when(r.completedAt);
    if (!at || nowMs - at >= RECEIPT_MS || at - nowMs > 60000) return null;
    const trash = r.mode === "trash";
    const done = Math.round(num(r.deletedCount));
    const failed = Math.round(num(r.failedCount));
    const skipped = Math.round(num(r.unattemptedCount));
    const moved = trash ? num(r.totalBytesMoved) || num(r.totalBytes) : num(r.totalBytesFreed);
    return { id, mode: trash ? "trash" : "delete", done, failed, skipped, stopped: r.stopped === true, bytes: moved };
}

/**
 * @param {number} n
 * @param {string} one
 * @param {string} many
 */
function count(n, one, many) { return n + " " + (n === 1 ? one : many); }

/** @param {{ mode: string, done: number, failed: number, skipped: number, stopped: boolean, bytes: number }} r */
export function receiptNotice(r) {
    const trash = r.mode === "trash";
    const what = r.bytes > 0 ? bytes(r.bytes) : count(r.done, "item", "items");
    const head = trash ? "Moved " + what + " to the Trash" : r.bytes > 0 ? "Freed " + what : "Removed " + what;
    if (r.failed > 0 || r.stopped) {
        const left = r.failed > 0 ? count(r.failed, "item stayed", "items stayed") : count(r.skipped, "item wasn't reached", "items weren't reached");
        return { tone: "warn", title: head + " · " + left,
            detail: r.failed > 0 ? "They were busy or not yours to remove. Look at them again in Sweep." : "The clear stopped early. Look at what's left in Sweep.",
            actionId: "reviewProject", actionLabel: "Look in Sweep" };
    }
    return { tone: "good", title: head,
        detail: trash ? count(r.done, "item is", "items are") + " in the Trash. The space comes back when you empty it." : count(r.done, "item", "items") + " removed.",
        actionId: "", actionLabel: "" };
}

/** @param {string} code */
export function errorCopy(code) {
    switch (code) {
    case "engine_missing": return { title: "Sweep's scanner is missing", detail: "Reinstalling Sweep brings it back." };
    case "permission_denied": return { title: "Sweep can't read your projects folder", detail: "Check that the folder belongs to you." };
    case "target_missing": return { title: "Your projects folder isn't there", detail: "Sweep looks in Projects in your home folder." };
    case "timeout": return { title: "Counting took too long", detail: "Large folders can take a while. Try again when the computer is idle." };
    case "schema_mismatch": return { title: "Sweep and kuwai don't match", detail: "Update both so they speak the same version." };
    case "not_installed": return { title: "Sweep isn't installed", detail: "Install it to see what your old projects hold." };
    default: return { title: "Couldn't count your projects", detail: "Sweep stopped before it finished." };
    }
}

/** @param {number} days */
export function idleText(days) {
    const d = Math.max(0, Math.round(Number(days) || 0));
    if (d >= 365) return Math.floor(d / 365) + (d >= 730 ? " years" : " year");
    if (d >= 60) return Math.floor(d / 30) + " months";
    return d + (d === 1 ? " day" : " days");
}

/**
 * @param {number} atMs
 * @param {number} nowMs
 */
export function agoText(atMs, nowMs) {
    if (!(atMs > 0)) return "";
    const m = Math.max(0, Math.round((nowMs - atMs) / 60000));
    return m < 1 ? "just now" : m < 60 ? m + " min ago" : m < 1440 ? Math.round(m / 60) + " h ago" : Math.round(m / 1440) + " d ago";
}

/** @param {Part[]} parts */
function buckets(parts) {
    const sorted = parts.slice().sort((a, b) => b.bytes - a.bytes);
    const room = sorted.length > MAX_BUCKETS ? MAX_BUCKETS - 1 : MAX_BUCKETS;
    const keep = sorted.slice(0, room);
    const rest = sorted.slice(room).reduce((t, p) => t + p.bytes, 0);
    const out = keep.map((p, i) => ({ id: "b" + i, label: p.label, value: p.bytes,
        detail: bytes(p.bytes) + (p.count ? " · " + count(p.count, "folder", "folders") : "") + (p.hint ? " · " + p.hint : ""),
        tone: "neutral" }));
    if (rest > 0) out.push({ id: "rest", label: "Everything else", value: rest, detail: bytes(rest), tone: "muted" });
    return out;
}

/**
 * @typedef {{ nowMs: number, onBattery: boolean, scanning: boolean, installed: boolean | null, apply: ReturnType<typeof activeApply>,
 *   receipt: ReturnType<typeof receipt>, copied: boolean, reviewing: boolean, markOff: boolean }} Context
 */

/**
 * @param {Summary} s
 * @param {Context} c
 */
export function toPanel(s, c) {
    const installed = s.installed === false ? false
        : s.source === "widget" || (s.installed === true && (counted(s) || s.pending || s.refreshing || !!s.error)) ? true : c.installed;
    /** @type {any} */
    const p = { kuwaiPanelSchema: SCHEMA, id: "sweep", title: "Idle projects", state: "ready", footnote: SAFETY };
    if (installed === false) {
        p.state = "not_installed";
        p.empty = { icon: "broom", title: "Sweep isn't installed",
            detail: "Sweep finds the build folders and caches your old projects hold. Copy the install command and run it in a terminal.",
            actionId: "copyInstall", actionLabel: c.copied ? "Copied ✓" : "Copy install command" };
        p.primaryAction = { id: "openUrl", label: "About Sweep", url: HELP_URL };
        p.footnote = "";
        return p;
    }
    if (c.apply) {
        const a = c.apply;
        p.state = "busy";
        p.hero = { value: a.total ? "Clearing " + a.done + " of " + a.total : "Clearing", tone: "info",
            label: a.bytes > 0 ? (a.mode === "trash" ? "About " + bytes(a.bytes) + " moved to the Trash so far" : "About " + bytes(a.bytes) + " freed so far") : "Starting",
            detail: a.failed ? count(a.failed, "item stayed", "items stayed") : "" };
        if (a.total) p.visualization = { type: "meter", total: a.total, label: "Progress", buckets: [{ id: "done", label: "Done", value: Math.min(a.done, a.total), detail: a.done + " of " + a.total, tone: "info" }] };
        p.footnote = "Running in your Sweep terminal. Stop it there if you need to.";
        return p;
    }
    const known = counted(s);
    if (!known) {
        if (s.error) {
            const e = errorCopy(s.error);
            p.state = "error";
            p.notice = s.error === "schema_mismatch" ? { tone: "bad", title: e.title, detail: e.detail, actionId: "openUrl", actionLabel: "How to update", url: HELP_URL }
                : { tone: "bad", title: e.title, detail: e.detail, actionId: "refresh", actionLabel: "Try again" };
            return p;
        }
        if (c.scanning || s.pending || s.refreshing || installed === null || !c.onBattery) {
            p.state = "loading";
            p.subtitle = "Counting your projects… the first count can take a minute.";
            return p;
        }
        p.state = "stale";
        p.notice = { tone: "warn", title: "Not counted yet", detail: "On battery, kuwai waits for you before it counts.", actionId: "refresh", actionLabel: "Count now" };
        return p;
    }
    const age = band(s.checkedAt, c.nowMs);
    const scanning = c.scanning || s.refreshing;
    if (s.idleBytes > 0) {
        p.hero = { value: bytes(s.idleBytes), label: count(s.idleProjects, "idle project", "idle projects"),
            detail: "untouched " + s.idleDays + "+ days" + (s.reclaimable > s.idleBytes ? " · " + bytes(s.reclaimable) + " across all projects" : ""), tone: "neutral" };
    } else if (s.reclaimable > 0) {
        p.hero = { value: bytes(s.reclaimable), label: "across all projects", detail: "None has been idle " + s.idleDays + "+ days", tone: "neutral" };
    }
    const parts = buckets(s.parts);
    if (parts.length) p.visualization = { type: "dotBar", label: s.idleBytes > 0 && s.source === "legacy" ? "What the idle projects hold" : "What it's made of", buckets: parts,
        total: parts.reduce((t, b) => t + b.value, 0) };
    p.rows = s.projects.slice(0, MAX_ROWS).map((pr, i) => ({ id: "p" + i, title: (pr.repo ? pr.repo + " › " : "") + pr.name,
        meta: idleText(pr.idleDays) + " · " + bytes(pr.bytes), actionId: "reviewProject" }));
    if (p.rows.length) p.rowsLabel = "Holding the most";
    if (!p.hero && !p.rows.length) {
        p.state = "empty";
        p.empty = { icon: "check-circle", title: "Nothing to clear", detail: "Your projects aren't holding build folders or caches worth clearing." };
    }
    if (c.receipt) p.notice = receiptNotice(c.receipt);
    else if (s.error) {
        const e = errorCopy(s.error);
        p.notice = { tone: "warn", title: "Couldn't count again", detail: e.title + ". What's shown is from " + agoText(s.checkedAt, c.nowMs) + ".", actionId: "refresh", actionLabel: "Try again" };
    } else if (age === "stale" && !scanning) {
        if (p.state === "ready") p.state = "stale";
        p.notice = { tone: "warn", title: "Counted " + agoText(s.checkedAt, c.nowMs), detail: c.onBattery ? "On battery, kuwai waits for you before it counts again." : "This may have changed since.",
            actionId: "refresh", actionLabel: "Count again" };
    } else if (s.partial) {
        p.notice = { tone: "info", title: "Some folders couldn't be read", detail: "The totals leave them out." };
    }
    if (p.state !== "empty") p.primaryAction = { id: "reviewProject", label: c.reviewing ? "Review open in Sweep" : "Review in Sweep" };
    const foot = [scanning ? "counting again…" : "counted " + agoText(s.checkedAt, c.nowMs), s.protectedCount > 0 ? s.protectedCount + " protected" : ""]
        .filter(x => x).join(" · ");
    p.footnote = SAFETY + (foot ? " " + foot.charAt(0).toUpperCase() + foot.slice(1) + "." : "") + (c.markOff ? " The idle projects mark is off in Settings → Island." : "");
    return p;
}

/**
 * @param {Summary} s
 * @param {string} rowId
 * @param {string} home
 */
export function reviewDir(s, rowId, home) {
    const m = /^p(\d{1,2})$/.exec(String(rowId || ""));
    const p = m ? s.projects[Number(m[1])] : null;
    const dir = p && p.path ? p.path : s.root || String(home || "").replace(/\/+$/, "") + "/Projects";
    return typeof dir === "string" && dir.startsWith("/") && !CONTROL.test(dir) && !/(^|\/)\.\.(\/|$)/.test(dir) ? dir : "";
}

/**
 * @param {unknown} raw
 * @returns {string}
 */
export function parseDismissed(raw) {
    try {
        const o = JSON.parse(String(raw || ""));
        return isObj(o) && typeof o.dismissedReceiptId === "string" ? o.dismissedReceiptId.slice(0, 64) : "";
    } catch (e) { return ""; }
}

/** @param {string} id */
export function dismissedText(id) {
    return JSON.stringify({ dismissedReceiptId: id }) + "\n";
}
