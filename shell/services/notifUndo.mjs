// Undo for clearing notifications: what a clear took, where each one stood,
// and how to put them back.
//
// A clear (one row, one app, or all) used to end each notification at once:
// out of the list, its sender told it was dismissed, the item destroyed and
// the history file rewritten without it. One slip of "Clear" lost the day.
// Now a clear is held for Theme.undoMs: the items leave the list and the file
// at once (so a restart during the window keeps the clear: what you asked for
// stays done, and nothing a person cleared comes back by surprise), but they
// stay alive in memory, their senders not yet told. Undo puts them back where
// they stood; the window passing ends them as a clear always did.
//
// Clears from the same surface inside one window add up (⌫ three times, then
// ⌃Z, brings back three); a clear from another surface ends the first batch,
// since only the surface that cleared shows the way back.
//
// Never held: what the caller's `keep` refuses. Notifs refuses one-time codes
// (a secret the person just removed is not kept around or shown again) and
// anything already on its way out (acted on, being forgotten).
//
// Read/unread is not stored: an item is unread while its time is after
// Notifs.lastSeen, and its time is untouched, so it comes back exactly as
// read as it would be had it never been cleared.
//
// Plain ES for Qt's engine: no object spread, no lookbehind, no named groups.
// Typed with JSDoc and checked by tsc (tsconfig.check.json).
// `bun test tests/shell/notif-undo.test.mjs`
// @ts-check

/** A notification (NotifItem); only its identity matters here. @typedef {object} Item */
/**
 * What one window holds.
 * @typedef {{ surface: string, order: Item[], held: Item[] }} Batch
 *   surface  who cleared ("center" | "island"): the one that shows "Cleared N · Undo"
 *   order    the list as it stood, held items included: where each goes back
 *   held     what Undo brings back, in list order
 */

/**
 * `current` with `back` put where they stood in `order`: each after the
 * nearest item above it in `order` that is still there; with none, after
 * whatever arrived since (newest first, so they stay on top).
 * @param {Item[]} current
 * @param {Item[]} order
 * @param {Item[]} back
 * @returns {Item[]}
 */
export function place(current, order, back) {
    const out = current.filter(i => back.indexOf(i) < 0);
    for (let k = 0; k < order.length; k++) {
        const x = order[k];
        if (back.indexOf(x) < 0) continue;
        let at = -1;
        for (let j = k - 1; j >= 0 && at < 0; j--) at = out.indexOf(order[j]);
        if (at >= 0) { out.splice(at + 1, 0, x); continue; }
        // Nothing of the old list above it: below the newcomers, above the rest.
        let first = out.length;
        for (let j = 0; j < out.length; j++) if (order.indexOf(out[j]) >= 0) { first = j; break; }
        out.splice(first, 0, x);
    }
    return out;
}

/**
 * A clear happened: hold what it took.
 * @param {Batch | null} batch   the window still open, if any
 * @param {string} surface
 * @param {Item[]} list          the list just before this clear
 * @param {Item[]} gone          what this clear takes
 * @param {(item: Item) => boolean} keep   false: ended now, never held
 * @returns {{ batch: Batch | null, end: Item[] }}
 *   batch  the window to show (null: nothing to undo)
 *   end    to end for good now: refused ones, and an earlier batch from another surface
 */
export function take(batch, surface, list, gone, keep) {
    /** @type {Item[]} */
    const end = [];
    let prev = batch;
    if (prev && prev.surface !== surface) {
        for (const i of prev.held) end.push(i);
        prev = null;
    }
    /** @type {Item[]} */
    const fresh = [];
    for (const i of gone) {
        if (fresh.indexOf(i) >= 0 || (prev && prev.held.indexOf(i) >= 0)) continue;
        if (keep(i)) fresh.push(i);
        else end.push(i);
    }
    if (!prev && !fresh.length) return { batch: null, end: end };
    // The earlier clear's items are already out of `list`: put them back into
    // the order so both clears go back to where they stood.
    const order = prev ? place(list, prev.order, prev.held) : list.slice();
    const held = order.filter(i => fresh.indexOf(i) >= 0 || (!!prev && prev.held.indexOf(i) >= 0));
    return { batch: { surface: surface, order: order, held: held }, end: end };
}

/**
 * One held item ended some other way (its app withdrew it): it can't come back.
 * @param {Batch | null} batch
 * @param {Item} item
 * @returns {Batch | null}  null once nothing is left to undo
 */
export function forget(batch, item) {
    if (!batch || batch.held.indexOf(item) < 0) return batch;
    const held = batch.held.filter(i => i !== item);
    if (!held.length) return null;
    return { surface: batch.surface, order: batch.order.filter(i => i !== item), held: held };
}

/**
 * Undo: the list with the batch's items back where they stood.
 * @param {Batch} batch
 * @param {Item[]} current
 * @returns {Item[]}
 */
export function restore(batch, current) {
    return place(current, batch.order, batch.held);
}

/**
 * Is it held right now (out of the list and the file, not ended)?
 * @param {Batch | null} batch
 * @param {Item} item
 */
export function isHeld(batch, item) {
    return !!batch && batch.held.indexOf(item) >= 0;
}

/**
 * What the history file gets: never a held item, even one still in the list
 * while its toast leaves, never one already on its way out, and never a
 * secret (a one-time code lives in memory only: a file outlives its minutes).
 * @param {Item[]} items
 * @param {Item[]} snoozed
 * @param {Batch | null} batch
 * @param {(item: Item) => boolean} [secret]
 * @returns {Item[]}
 */
export function persisted(items, snoozed, batch, secret) {
    return items.concat(snoozed).filter(i => !(/** @type {{ discard?: boolean, fleeting?: boolean }} */ (i)).discard && !(/** @type {{ fleeting?: boolean }} */ (i)).fleeting && !isHeld(batch, i) && !(secret && secret(i)));
}

/**
 * The one line: "Cleared 3 · Undo"; "" when there is nothing to undo.
 * @param {Batch | null} batch
 */
export function label(batch) {
    return batch && batch.held.length ? "Cleared " + batch.held.length + " · Undo" : "";
}
