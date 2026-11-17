.pragma library
// What the island says about idle projects (services/Sweep, SweepPanel,
// SysMarks): sizes, the mark's value, the bar's segments, what is worth a
// mark. Pure, so tests/shell/sweep-model.test.mjs can hold it to account.
//   compact(bytes)                      → "16G" / "9.5G" / "640M"
//   segments(kinds, total, tones)       → [{ kind, bytes, count, share, tone }] (top kinds + "other")
//   headline(bytes, projects, days)     → "16.2 GB · 38 projects idle 30+ days"
//   caption(seg, idleSplit, allBytes)   → the words under the bar
//   worthMark(idleBytes, minBytes)      → bool
//   parseViewed(text) / viewedText(b)   ↔ the sweep-viewed file: the size you looked at, in bytes
//   isFresh(idle, viewed, min)          → bool: worth a mark and new, or 5 GB past what you saw
//   reconcileViewed / viewedAfterLook   → what that stored size becomes
//   tilde / emptyText(state) / footText(state, now)  → the panel's words for its states
//   idleText(days) / agoText(sec, now)  → "7 months" / "12 min ago" ("" before the first count)

const GB = 1e9;

function compact(bytes) {
    const b = Math.max(0, Number(bytes) || 0);
    if (b >= 10 * GB) return Math.round(b / GB) + "G";
    if (b >= GB) return (Math.round(b / GB * 10) / 10) + "G";
    return Math.max(1, Math.round(b / 1e6)) + "M";
}

// "16.2 GB" for the panel, where there is room for the unit.
function long(bytes) {
    const b = Math.max(0, Number(bytes) || 0);
    if (b >= GB) return (b >= 100 * GB ? Math.round(b / GB) : Math.round(b / GB * 10) / 10) + " GB";
    return Math.max(1, Math.round(b / 1e6)) + " MB";
}

// The bar: each kind's share of what could be freed. Kinds under 4 % (or past
// `max`) fold into one "other", so the bar has few, readable parts.
function segments(kinds, total, tones, max) {
    const cap = max || 4, sum = Number(total) || 0;
    if (!Array.isArray(kinds) || sum <= 0) return [];
    const sorted = kinds.filter(k => k && k.bytes > 0).slice().sort((a, b) => b.bytes - a.bytes);
    if (!sorted.length) return [];
    const keep = [];
    let rest = sum;
    for (const k of sorted) {
        if (keep.length >= cap || k.bytes / sum < 0.04) break;
        keep.push({ kind: k.kind, bytes: k.bytes, count: k.count || 0, share: k.bytes / sum });
        rest -= k.bytes;
    }
    if (rest > sum * 0.005) keep.push({ kind: "other", bytes: rest, count: 0, share: rest / sum });
    return keep.map((s, i) => Object.assign(s, { tone: tones[i % tones.length] }));
}

// The header's line: "16.2 GB · 38 projects idle 30+ days".
function headline(idleBytes, projects, days) {
    const n = Math.max(0, Math.round(Number(projects) || 0));
    return long(idleBytes) + " · " + n + (n === 1 ? " project" : " projects") + " idle " + (Math.round(Number(days) || 30)) + "+ days";
}

// The bar's caption. `idleSplit`: the bar is the idle projects alone, so its
// total is the header's number. Without it (a sweep whose status has no
// idle split) the bar is everything sweep found, and the words say so.
function caption(seg, idleSplit, allBytes) {
    if (!seg) return idleSplit ? "What the idle projects hold · rest on a part"
        : "All projects, idle or not: " + long(allBytes) + " · rest on a part";
    return (seg.kind === "other" ? "Everything else" : seg.kind) + " · " + long(seg.bytes)
        + (seg.count ? " · " + seg.count + (seg.count === 1 ? " folder" : " folders") : "")
        + (idleSplit ? "" : " · all projects");
}

// A mark only when there is something worth saying: a number you would act on.
function worthMark(idleBytes, minBytes) {
    return (Number(idleBytes) || 0) >= Math.max(1, Number(minBytes) || 0);
}

// Looking at it is enough until the number grows by another 5 GB past what
// you looked at. The size is kept in bytes (a 5 GB *step* key resurfaced the
// mark going from 14.9 to 15.0 GB).
const STEP = 5 * GB;

// The sweep-viewed file → the idle size last looked at, in bytes, or null
// (unseen). Today's form is {"bytes":N}; the older one was the step key ("3":
// looked at somewhere in 15–20 GB), read as that step's floor so it comes back
// where it used to. Anything else is unseen.
function parseViewed(text) {
    const t = String(text === undefined || text === null ? "" : text).trim();
    if (!t) return null;
    if (/^\d{1,6}$/.test(t)) return Number(t) * STEP;
    try {
        const o = JSON.parse(t);
        if (o && typeof o === "object" && typeof o.bytes === "number" && isFinite(o.bytes) && o.bytes >= 0) return o.bytes;
    } catch (e) {}
    return null;
}
function viewedText(bytes) {
    return bytes === null || bytes === undefined ? "" : JSON.stringify({ bytes: Math.round(Number(bytes) || 0) }) + "\n";
}

// The mark shows when the number is worth acting on and either new to you or
// 5 GB past what you looked at.
function isFresh(idleBytes, viewedBytes, minBytes) {
    if (!worthMark(idleBytes, minBytes)) return false;
    return viewedBytes === null || viewedBytes === undefined || Number(idleBytes) >= Number(viewedBytes) + STEP;
}

// What the stored size becomes as the number moves (no one looking): under the
// threshold it is forgotten (the next time it's worth a mark, it's new);
// after a clean-up it follows the number down, so "another 5 GB" counts from
// what is left, not from before.
function reconcileViewed(idleBytes, viewedBytes, minBytes) {
    if (viewedBytes === null || viewedBytes === undefined) return null;
    const idle = Number(idleBytes) || 0;
    if (!worthMark(idle, minBytes)) return null;
    return idle < viewedBytes ? idle : viewedBytes;
}

// Looking now: the size to keep (null: nothing to keep, below the threshold).
function viewedAfterLook(idleBytes, viewedBytes, minBytes) {
    const idle = Number(idleBytes) || 0;
    if (!worthMark(idle, minBytes)) return viewedBytes === undefined ? null : viewedBytes;
    return viewedBytes === null || viewedBytes === undefined ? idle : Math.max(idle, Number(viewedBytes));
}

// "~/Projects" for a path under home.
function tilde(path, home) {
    const p = String(path || ""), h = String(home || "").replace(/\/+$/, "");
    return h && (p === h || p.startsWith(h + "/")) ? "~" + p.slice(h.length) : p;
}

// What the panel says when it has no bar to show (""), from Sweep's state:
//   { loaded, alive, pending, error, counted, root, home, hasBar }
function emptyText(s) {
    if (!s.loaded) return "Looking for sweep…";
    // The command is sweep's README's (the review needs its terminal UI).
    if (!s.alive) return "sweep isn't installed — bun add -g @kitsunekode/sweep @opentui/core";
    if (s.error && !s.counted) return "Couldn't count " + tilde(s.root, s.home) + ": " + s.error + ".";
    if (s.pending) return "Counting " + tilde(s.root, s.home) + "…  the first scan can take a minute.";
    if (!s.hasBar) return "Nothing to free here.";
    return "";
}

// The footer: protected items, when it was counted, and what the count is
// doing now: { protectedCount, checkedAt, pending, refreshing, error, counted }.
function footText(s, nowMs) {
    const ago = s.counted && !s.pending ? agoText(s.checkedAt, nowMs) : "";
    return [
        s.protectedCount > 0 ? s.protectedCount + " protected" : "",
        ago ? "counted " + ago : "",
        s.counted && s.refreshing ? "counting again…" : s.counted && s.error ? "couldn't count again: " + s.error : "",
    ].filter(x => x).join(" · ");
}

function idleText(days) {
    const d = Math.max(0, Math.round(Number(days) || 0));
    if (d >= 365) return Math.floor(d / 365) + (d >= 730 ? " years" : " year");
    if (d >= 60) return Math.floor(d / 30) + " months";
    return d + " days";
}

// "" while nothing has been counted yet (checkedAt 0: pending, or every try
// failed): never "counted 20410 d ago".
function agoText(checkedAtSec, nowMs) {
    if (!(Number(checkedAtSec) > 0)) return "";
    const m = Math.max(0, Math.round((nowMs - checkedAtSec * 1000) / 60000));
    return m < 1 ? "just now" : m < 60 ? m + " min ago" : m < 1440 ? Math.round(m / 60) + " h ago" : Math.round(m / 1440) + " d ago";
}
