.pragma library
.import "sizes.mjs" as Sizes

const GB = Sizes.GB;

function compact(bytes) {
    return Sizes.compact(bytes);
}

function long(bytes) {
    const b = Math.max(0, Number(bytes) || 0);
    return b < Sizes.MB ? "1 MB" : Sizes.bytes(b, 100);
}

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

function where(path, name) {
    const p = String(path || "").replace(/\/+$/, "");
    const m = /\/([^/]+)\/(?:\.worktrees|\.claude\/worktrees)\/([^/]+)$/.exec(p);
    if (m) return { repo: m[1], name: m[2] };
    return { repo: "", name: String(name || p.slice(p.lastIndexOf("/") + 1) || p) };
}

function headline(idleBytes, projects, days) {
    const n = Math.max(0, Math.round(Number(projects) || 0));
    return long(idleBytes) + " · " + n + (n === 1 ? " project" : " projects") + " idle " + (Math.round(Number(days) || 30)) + "+ days";
}

function widths(segs, width, gap) {
    if (!Array.isArray(segs) || !segs.length) return [];
    const room = Math.max(0, (Number(width) || 0) - (segs.length - 1) * gap);
    return segs.map(s => Math.max(4, Math.round(s.share * room)));
}

function partAt(x, ws, gap) {
    if (!Array.isArray(ws) || !ws.length) return -1;
    let end = 0;
    for (let i = 0; i < ws.length; i++) {
        end += ws[i];
        if (x < end + gap / 2) return i;
        end += gap;
    }
    return ws.length - 1;
}

function caption(seg, idleSplit, allBytes) {
    if (!seg) return idleSplit ? "What the idle projects hold · rest on a part"
        : "All projects, idle or not: " + long(allBytes) + " · rest on a part";
    return (seg.kind === "other" ? "Everything else" : seg.kind) + " · " + long(seg.bytes)
        + (seg.count ? " · " + seg.count + (seg.count === 1 ? " folder" : " folders") : "")
        + (idleSplit ? "" : " · all projects");
}

function worthMark(idleBytes, minBytes) {
    return (Number(idleBytes) || 0) >= Math.max(1, Number(minBytes) || 0);
}

const STEP = 5 * GB;

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

function isFresh(idleBytes, viewedBytes, minBytes) {
    if (!worthMark(idleBytes, minBytes)) return false;
    return viewedBytes === null || viewedBytes === undefined || Number(idleBytes) >= Number(viewedBytes) + STEP;
}

function reconcileViewed(idleBytes, viewedBytes, minBytes) {
    if (viewedBytes === null || viewedBytes === undefined) return null;
    const idle = Number(idleBytes) || 0;
    if (!worthMark(idle, minBytes)) return null;
    return idle < viewedBytes ? idle : viewedBytes;
}

function viewedAfterLook(idleBytes, viewedBytes, minBytes) {
    const idle = Number(idleBytes) || 0;
    if (!worthMark(idle, minBytes)) return viewedBytes === undefined ? null : viewedBytes;
    return viewedBytes === null || viewedBytes === undefined ? idle : Math.max(idle, Number(viewedBytes));
}

function tilde(path, home) {
    const p = String(path || ""), h = String(home || "").replace(/\/+$/, "");
    return h && (p === h || p.startsWith(h + "/")) ? "~" + p.slice(h.length) : p;
}

function emptyText(s) {
    if (!s.loaded) return "Looking for Sweep…";
    if (!s.alive) return "Sweep isn't installed. Add it with: bun add -g @kitsunekode/sweep @opentui/core";
    if (s.error && !s.counted) return "Couldn't count " + tilde(s.root, s.home) + ": " + s.error + ".";
    if (s.pending) return "Counting " + tilde(s.root, s.home) + "…  the first scan can take a minute.";
    if (!s.hasBar) return "Nothing to free here.";
    return "";
}

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

function agoText(checkedAtSec, nowMs) {
    if (!(Number(checkedAtSec) > 0)) return "";
    const m = Math.max(0, Math.round((nowMs - checkedAtSec * 1000) / 60000));
    return m < 1 ? "just now" : m < 60 ? m + " min ago" : m < 1440 ? Math.round(m / 60) + " h ago" : Math.round(m / 1440) + " d ago";
}
