.pragma library
// What the island says about idle projects (services/Sweep, SweepPanel,
// SysMarks): sizes, the mark's value, the bar's segments, what is worth a
// mark. Pure, so tests/shell/sweep-model.test.mjs can hold it to account.
//   compact(bytes)                      → "16G" / "9.5G" / "640M"
//   segments(kinds, total, tones)       → [{ kind, bytes, count, share, tone }] (top kinds + "other")
//   worthMark(idleBytes, minBytes)      → bool
//   seenKey(idleBytes)                  → "3": the 5 GB step this size is in
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

// A mark only when there is something worth saying: a number you would act on.
function worthMark(idleBytes, minBytes) {
    return (Number(idleBytes) || 0) >= Math.max(1, Number(minBytes) || 0);
}

// Looking at it is enough until the number grows by another 5 GB.
function seenKey(idleBytes) {
    return String(Math.floor((Number(idleBytes) || 0) / (5 * GB)));
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
