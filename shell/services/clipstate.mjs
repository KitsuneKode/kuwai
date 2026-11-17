// The clipboard panel's two pieces of bookkeeping (modules/clipboard and
// services/Clipboard.qml), kept here so they can be tested with bun:
//
// 1. What is over the shelf: one `mode`, never a pile of booleans.
//
//    The panel had ten flags and an `open` on each sub-surface, and opening
//    one never closed another: ⌃D opened the calendar under an open action
//    menu, F1 put the key sheet over Quick Look and the naming field, ⌃K put
//    the menu over Quick Look. Now there is one mode and every surface reads
//    its own `open` from it, so two can't show at once.
//
//      browse ─┬─ quicklook ── edit        (Quick Look; editing its text)
//              ├─ naming                   (⌃S on an image: the file's name)
//              ├─ actions                  (⌃K)
//              ├─ filter                   (the type menu)
//              ├─ date                     (⌃D)
//              ├─ keys                     (F1, ⌃/, ?)
//              └─ confirmWipe              (⌃⇧⌫ once: "press again")
//
//    Esc steps back exactly one level along that tree: edit → quicklook →
//    browse; every other overlay → browse. In browse it undoes one thing at
//    a time: the marks, then the search text, then the type filter, then the
//    date range, then it closes the panel (escapeStep).
//
// 2. Deleting a copy can be undone (⌃Z) for Theme.undoMs.
//
//    History is cliphist's, and cliphist can't put a copy back where it was
//    (a store lands on top with a new id). So a delete is held, not done:
//    the entry is hidden (`visible`), a pin is taken out of the pin list and
//    remembered with its place, and the real `cliphist delete` / unpin runs
//    when the window ends, when the panel closes, or, if the shell restarts
//    in between, at the next start (the held ids are written to the state
//    file, so a restart purges them instead of showing them again). Secrets
//    are held like anything else and purged the same way. Clearing the whole
//    history is immediate and can't be undone; the panel says so.
//
// Plain ES for Qt's engine: no object spread, no lookbehind, no named groups.
// Typed with JSDoc and checked by tsc (tsconfig.check.json); nothing compiled.
// Quickshell reloads on QML changes only: after editing this file, save a QML
// file that imports it too (or restart), or the old rules keep running.
// @ts-check

// ── 1. Modes ──────────────────────────────────────────────────────────────

/** @typedef {"browse"|"quicklook"|"edit"|"naming"|"actions"|"filter"|"date"|"keys"|"confirmWipe"} Mode */

/** Every mode, browse first. @type {Mode[]} */
export const MODES = ["browse", "quicklook", "edit", "naming", "actions", "filter", "date", "keys", "confirmWipe"];

/** One level up from each mode: where Esc goes. @type {Record<Mode, Mode>} */
const PARENT = {
    browse: "browse", quicklook: "browse", edit: "quicklook", naming: "browse",
    actions: "browse", filter: "browse", date: "browse", keys: "browse", confirmWipe: "browse"
};

/** @param {string} m @returns {m is Mode} */
export function isMode(m) { return MODES.indexOf(/** @type {Mode} */ (m)) >= 0; }

/** @param {string} m @returns {Mode} */
export function parentOf(m) { return isMode(m) ? PARENT[m] : "browse"; }

/** The same key again closes what it opened. @param {string} current @param {string} m @returns {Mode} */
export function toggle(current, m) {
    const cur = isMode(current) ? current : "browse";
    if (!isMode(m)) return cur;
    return cur === m ? PARENT[m] : m;
}

/** A surface closed itself (a click outside, a pick): back up, if it was the one showing.
 * @param {string} current @param {string} m @returns {Mode} */
export function leave(current, m) {
    const cur = isMode(current) ? current : "browse";
    return cur === m ? parentOf(m) : cur;
}

/** @typedef {{ quickLook: boolean, editing: boolean, naming: boolean, actionMenu: boolean, filterMenu: boolean, datePicker: boolean, keySheet: boolean, confirmWipe: boolean }} Surfaces */

/** What shows in a mode. Editing happens inside Quick Look, so both are true in "edit".
 * @param {string} mode @returns {Surfaces} */
export function surfaces(mode) {
    return {
        quickLook: mode === "quicklook" || mode === "edit",
        editing: mode === "edit",
        naming: mode === "naming",
        actionMenu: mode === "actions",
        filterMenu: mode === "filter",
        datePicker: mode === "date",
        keySheet: mode === "keys",
        confirmWipe: mode === "confirmWipe"
    };
}

/** The overlays that are drawn over the shelf (editing is Quick Look's own state, not a surface). */
export const OVERLAYS = ["quickLook", "naming", "actionMenu", "filterMenu", "datePicker", "keySheet", "confirmWipe"];

/** How many overlays a mode shows (0 or 1, by construction). @param {string} mode */
export function overlayCount(mode) {
    const s = /** @type {Record<string, boolean>} */ (surfaces(mode));
    let n = 0;
    for (const k of OVERLAYS) if (s[k]) n++;
    return n;
}

/** Modes that keep the panel from putting itself away while idle (you're in the middle of something).
 * Quick Look alone doesn't (it never did); reading it large does, and the panel checks that itself.
 * @param {string} mode */
export function holdsOpen(mode) {
    return mode === "edit" || mode === "naming" || mode === "actions" || mode === "date" || mode === "keys";
}

/** A key, as the panel names it for routing:
 *   escape · help (F1, ⌃/) · question (? in an empty search) · actions (⌃K) · date (⌃D)
 *   look (Space, ⌃Y) · read (⇧Space) · wipe (⌃⇧⌫) · modifier (⌃ ⇧ ⌘ alone) · other
 * @typedef {"escape"|"help"|"question"|"actions"|"date"|"look"|"read"|"wipe"|"modifier"|"other"} Chord */

/** What to do with a key:
 *   mode  set this mode first (when present)
 *   next  "done" (handled) · "overlay" (the open menu or calendar gets it; if it doesn't
 *         take it, the shelf does) · "shelf" (the shelf's own keys) · "ignore" (not ours)
 * @typedef {{ mode?: Mode, next: "done"|"overlay"|"shelf"|"ignore" }} Route */

/** Where a key goes in a mode. Every mode change goes through here or toggle/leave, so the
 * one-overlay rule can't be broken by a key arriving in an unexpected order.
 * @param {string} current @param {Chord} chord @returns {Route} */
export function route(current, chord) {
    const mode = isMode(current) ? current : "browse";
    if (chord === "modifier") return { next: "ignore" };
    // The key sheet: any key closes it, and that key does nothing else.
    if (mode === "keys") return { mode: "browse", next: "done" };
    // Typing a name or an edit: those fields own their keys; Esc is theirs too, but
    // if one reaches the panel it still backs out one level and nothing else opens.
    if (mode === "edit" || mode === "naming") return chord === "escape" ? { mode: PARENT[mode], next: "done" } : { next: "ignore" };
    if (chord === "escape") return mode === "browse" ? { next: "shelf" } : { mode: PARENT[mode], next: "done" };
    if (chord === "help") return { mode: "keys", next: "done" };
    if (chord === "actions") return { mode: toggle(mode, "actions"), next: "done" };
    if (chord === "date") return { mode: toggle(mode, "date"), next: "done" };
    const menu = mode === "actions" || mode === "filter";
    // In a menu, ? and Space are letters of its filter.
    if (chord === "question") return menu ? { next: "overlay" } : { mode: "keys", next: "done" };
    // Clear history: the shelf asks first (confirmWipe) or does it (already asking).
    if (chord === "wipe") return { next: "shelf" };
    if (mode === "confirmWipe") return { mode: "browse", next: "shelf" };   // any other key: never mind
    if (mode === "actions" || mode === "filter" || mode === "date") return { next: "overlay" };
    return { next: "shelf" };
}

/** @typedef {{ marks: number, query: string, filter: string, date: boolean }} BrowseState */

/** What Esc does in browse, one thing at a time: "marks" · "query" · "filter" · "date" · "close".
 * @param {BrowseState} s */
export function escapeStep(s) {
    if (s.marks > 0) return "marks";
    if (s.query !== "") return "query";
    if (s.filter !== "all") return "filter";
    if (s.date) return "date";
    return "close";
}

// ── 2. Undo for delete ────────────────────────────────────────────────────

/** An entry as the service has it (only what this needs). @typedef {{ id: string, pin: string, secret?: boolean }} Entry */
/** A held pin and where it was in the pin list. @typedef {{ pin: string, at: number, entry: Entry }} HeldPin */
/** One delete (one card, or every marked card). @typedef {{ ids: string[], pins: HeldPin[], secrets: string[] }} Batch */
/** Everything held. `until`: when the window ends (ms). `gone`: ids already deleted for real, hidden
 * until cliphist's list stops showing them (a list read in the moment between).
 * @typedef {{ batches: Batch[], until: number, gone: Record<string, boolean> }} Holds */

/** @returns {Holds} */
export function empty() { return { batches: [], until: 0, gone: {} }; }

/** @param {Record<string, boolean>} m @returns {Record<string, boolean>} */
function copyMap(m) {
    /** @type {Record<string, boolean>} */
    const o = {};
    for (const k in m) o[k] = true;
    return o;
}

/** Hold a delete of these entries. `pins` is the current pin list (newest first): a pin's place in
 * it is remembered so undo can put it back there. The window restarts: it ends `ms` after the
 * latest delete, for every batch still held.
 * @param {Holds} h @param {Entry[]} entries @param {Entry[]} pins @param {number} now @param {number} ms @returns {Holds} */
export function hold(h, entries, pins, now, ms) {
    /** @type {Batch} */
    const b = { ids: [], pins: [], secrets: [] };
    const seen = held(h);
    for (const e of entries) {
        if (!e) continue;
        if (e.pin !== "") {
            const at = pins.findIndex(p => p.pin === e.pin);
            if (at >= 0 && !b.pins.some(p => p.pin === e.pin)) b.pins.push({ pin: e.pin, at: at, entry: pins[at] });
        } else if (e.id !== "" && !seen[e.id] && b.ids.indexOf(e.id) < 0) {
            b.ids.push(e.id);
            if (e.secret) b.secrets.push(e.id);
        }
    }
    if (!b.ids.length && !b.pins.length) return h;
    return { batches: h.batches.concat([b]), until: now + ms, gone: h.gone };
}

/** Ids hidden right now: held, or deleted and not yet gone from the list. @param {Holds} h */
export function held(h) {
    const out = copyMap(h.gone);
    for (const b of h.batches) for (const id of b.ids) out[id] = true;
    return out;
}

/** The history as the panel should see it: held and deleted ids left out, order kept.
 * @template {{ id: string }} T @param {T[]} items @param {Holds} h @returns {T[]} */
export function visible(items, h) {
    const hide = held(h);
    let any = false;
    for (const k in hide) { any = true; break; }
    return any ? items.filter(e => !hide[e.id]) : items;
}

/** The pin list without the held pins. @template {{ pin: string }} P @param {P[]} pins @param {Batch} b @returns {P[]} */
export function withoutPins(pins, b) {
    if (!b.pins.length) return pins;
    return pins.filter(p => !b.pins.some(x => x.pin === p.pin));
}

/** Put a batch's pins back where they were (lowest place first, so the places stay right).
 * @template P @param {P[]} pins @param {Batch} b @returns {Array<P|Entry>} */
export function withPins(pins, b) {
    /** @type {Array<P|Entry>} */
    const out = pins.slice();
    const back = b.pins.slice().sort((x, y) => x.at - y.at);
    for (const p of back) out.splice(Math.min(p.at, out.length), 0, p.entry);
    return out;
}

/** Can ⌃Z still bring something back? @param {Holds} h @param {number} now */
export function canUndo(h, now) { return h.batches.length > 0 && now < h.until; }

/** Undo the latest delete. After the window it's a no-op: `batch` is null and nothing changes
 * (what's held is about to be purged, and ⌃Z goes back to the search field).
 * @param {Holds} h @param {number} now @returns {{ holds: Holds, batch: Batch|null }} */
export function undo(h, now) {
    if (!canUndo(h, now)) return { holds: h, batch: null };
    const batch = h.batches[h.batches.length - 1];
    return { holds: { batches: h.batches.slice(0, -1), until: h.batches.length > 1 ? h.until : 0, gone: h.gone }, batch: batch };
}

/** End the window: everything held is to be deleted for real now. Ids move to `gone` (hidden until
 * the list stops showing them); `secrets` are the held ids that were secrets (their marks go too).
 * @param {Holds} h @returns {{ holds: Holds, ids: string[], pins: string[], secrets: string[] }} */
export function commit(h) {
    /** @type {string[]} */ const ids = [];
    /** @type {string[]} */ const pins = [];
    /** @type {string[]} */ const secrets = [];
    const gone = copyMap(h.gone);
    for (const b of h.batches) {
        for (const id of b.ids) { ids.push(id); gone[id] = true; }
        for (const p of b.pins) pins.push(p.pin);
        for (const s of b.secrets) secrets.push(s);
    }
    return { holds: { batches: [], until: 0, gone: gone }, ids: ids, pins: pins, secrets: secrets };
}

/** Ids being deleted outside a window (a purge at start): hidden until the list stops showing them.
 * @param {Holds} h @param {string[]} ids @returns {Holds} */
export function markGone(h, ids) {
    if (!ids.length) return h;
    const gone = copyMap(h.gone);
    for (const id of ids) gone[id] = true;
    return { batches: h.batches, until: h.until, gone: gone };
}

/** Forget deleted ids the list no longer has (cliphist never reuses an id).
 * @param {Holds} h @param {Array<{ id: string }>} items @returns {Holds} */
export function prune(h, items) {
    let any = false;
    for (const k in h.gone) { any = true; break; }
    if (!any) return h;
    /** @type {Record<string, boolean>} */ const live = {};
    for (const e of items) live[e.id] = true;
    /** @type {Record<string, boolean>} */ const gone = {};
    for (const k in h.gone) if (live[k]) gone[k] = true;
    return { batches: h.batches, until: h.until, gone: gone };
}

/** What the state file keeps, so a restart mid-window purges instead of showing the copies again.
 * @param {Holds} h @returns {{ ids: string[], pins: string[] }} */
export function toState(h) {
    const c = commit(h);
    return { ids: c.ids, pins: c.pins };
}

/** What a state file says is still to be purged (anything malformed is ignored).
 * @param {unknown} saved @returns {{ ids: string[], pins: string[] }} */
export function fromState(saved) {
    /** @param {unknown} v @returns {string[]} */
    const strings = v => Array.isArray(v) ? v.filter(x => typeof x === "string" && x !== "") : [];
    if (!saved || typeof saved !== "object") return { ids: [], pins: [] };
    const o = /** @type {{ ids?: unknown, pins?: unknown }} */ (saved);
    return { ids: strings(o.ids), pins: strings(o.pins) };
}

/** The keys (as the panel names cards) of a batch's entries, to select and mark them again.
 * @param {Batch} b @returns {string[]} */
export function keysOf(b) {
    /** @type {string[]} */ const out = [];
    for (const id of b.ids) out.push("i:" + id);
    for (const p of b.pins) out.push("p:" + p.pin);
    return out;
}
