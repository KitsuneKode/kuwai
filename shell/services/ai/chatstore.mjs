// @ts-check
// Where the assistant's chats live on disk, as pure functions
// (tests/shell/chatstore.test.mjs). OllamaService does the reading and
// writing; this decides what is written and how a file is understood.
//
//   $XDG_STATE_HOME/kuwai/ai-sessions.json   the list: { version: 2, chats: [Meta] }
//   $XDG_STATE_HOME/kuwai/ai-chats/<id>.json one chat:  Doc
//
// Only the open chat's messages (and a chat a turn is still answering in)
// are held in memory; the list is metadata. Before 2026-11-17 the list file
// was an array of whole chats (messages included): readIndex calls that
// "legacy" and the shell splits it once, never writing a chat file with
// fewer messages than one already on disk, and copying the original to
// ai-sessions.legacy.json first. Chat files are the truth: a chat file the
// list doesn't name (a list written by an older shell, a lost save) is put
// back on the list at start (orphansToMetas).
//
// Qt's engine loads this as written: no object spread, no regex lookbehind,
// no named groups. Quickshell reloads on QML changes only.

export const INDEX_VERSION = 2;

/** @typedef {{ id: string, title: string, renamed?: boolean, model: string, mode: string, updatedAt: number, count: number }} Meta */
/** @typedef {{ version: number, id: string, title: string, updatedAt: number, summary: string, summaryUpTo: number, messages: any[] }} Doc */
/** @typedef {{ kind: "empty" | "bad" | "newer" | "v2" | "legacy", chats: Meta[], docs: Doc[] }} Index */

/** Ids name files: digits and letters only (they are Date.now() strings). @param {any} id */
export function validId(id) { return typeof id === "string" && /^[A-Za-z0-9_-]{1,64}$/.test(id); }

/** @param {string} dir @param {any} id */
export function chatPath(dir, id) { return validId(id) ? dir + "/" + id + ".json" : ""; }

/**
 * The list's entry for a chat.
 * @param {any} s  a chat (metadata or an old whole chat)
 * @param {number} count  how many messages it has
 * @returns {Meta}
 */
export function metaOf(s, count) {
    /** @type {Meta} */
    const m = { id: String(s.id), title: String(s.title || "New Chat"), model: String(s.model || ""), mode: s.mode === "agent" ? "agent" : "chat",
        updatedAt: Number(s.updatedAt) || 0, count: Math.max(0, Number(count) || 0) };
    if (s.renamed) m.renamed = true;
    return m;
}

/** @param {Meta[]} chats */
export function indexText(chats) {
    return JSON.stringify({ version: INDEX_VERSION, chats: chats.map(c => metaOf(c, c.count)) }, null, 1);
}

/**
 * @param {any} meta
 * @param {any[]} messages
 * @param {string} summary
 * @param {number} summaryUpTo
 * @returns {Doc}
 */
export function chatDoc(meta, messages, summary, summaryUpTo) {
    return { version: INDEX_VERSION, id: String(meta.id), title: String(meta.title || "New Chat"), updatedAt: Number(meta.updatedAt) || 0,
        summary: String(summary || ""), summaryUpTo: Number(summaryUpTo) || 0, messages: messages || [] };
}

/** @param {Doc} d */
export function chatText(d) { return JSON.stringify(d); }

/**
 * A chat file, or null when it isn't one (missing, cut short, not ours).
 * @param {string} text
 * @returns {Doc | null}
 */
export function parseChat(text) {
    if (!text) return null;
    let d;
    try { d = JSON.parse(text); } catch (e) { return null; }
    if (!d || typeof d !== "object" || Array.isArray(d) || !Array.isArray(d.messages) || !validId(d.id)) return null;
    return chatDoc(d, d.messages, d.summary, d.summaryUpTo);
}

/**
 * Read the list file. "legacy": the old array of whole chats, with each one's
 * Doc to write. "bad": not JSON or not a list (the caller keeps a copy and
 * rebuilds the list from the chat files). "newer": a later version's list,
 * which this code must not overwrite.
 * @param {string} text
 * @returns {Index}
 */
export function readIndex(text) {
    if (!text || !text.trim()) return { kind: "empty", chats: [], docs: [] };
    let d;
    try { d = JSON.parse(text); } catch (e) { return { kind: "bad", chats: [], docs: [] }; }
    if (Array.isArray(d)) {
        /** @type {Meta[]} */ const chats = [];
        /** @type {Doc[]} */ const docs = [];
        const seen = /** @type {Record<string, boolean>} */ ({});
        for (const s of d) {
            if (!s || typeof s !== "object" || !validId(s.id) || seen[s.id]) continue;
            seen[s.id] = true;
            const msgs = Array.isArray(s.messages) ? s.messages : [];
            chats.push(metaOf(s, msgs.length));
            docs.push(chatDoc(s, msgs, s.summary, s.summaryUpTo));
        }
        return { kind: "legacy", chats: chats, docs: docs };
    }
    if (d && typeof d === "object" && Number(d.version) > INDEX_VERSION) return { kind: "newer", chats: [], docs: [] };
    if (!d || typeof d !== "object" || d.version !== INDEX_VERSION || !Array.isArray(d.chats)) return { kind: "bad", chats: [], docs: [] };
    /** @type {Meta[]} */ const chats = [];
    const seen = /** @type {Record<string, boolean>} */ ({});
    for (const s of d.chats) {
        if (!s || typeof s !== "object" || !validId(s.id) || seen[s.id]) continue;
        seen[s.id] = true;
        chats.push(metaOf(s, s.count));
    }
    return { kind: "v2", chats: chats, docs: [] };
}

/**
 * During the one-time split: write this chat's file only if what's on disk
 * for it isn't already as long (a split that ran before, or a later shell's
 * save). Never shrinks a chat.
 * @param {string} existingText  the chat file now ("" if none)
 * @param {Doc} doc
 */
export function shouldWriteLegacy(existingText, doc) {
    const cur = parseChat(existingText);
    return !cur || cur.messages.length < doc.messages.length;
}

/**
 * Chat files the list doesn't name, as list entries (newest first, after
 * the listed ones). Empty chats aren't worth listing.
 * @param {Meta[]} chats
 * @param {Doc[]} docs
 * @returns {Meta[]}
 */
export function orphansToMetas(chats, docs) {
    const have = /** @type {Record<string, boolean>} */ ({});
    for (const c of chats) have[c.id] = true;
    return docs.filter(d => d && !have[d.id] && d.messages.length > 0)
        .sort((a, b) => b.updatedAt - a.updatedAt)
        .map(d => metaOf({ id: d.id, title: d.title, updatedAt: d.updatedAt, renamed: d.title !== "New Chat" }, d.messages.length));
}

// ── Search (the open chat, in memory; the rest: kuwai-ollama find) ───────

/** @param {any} m */
function flat(m) { return String((m && m.text) || "").replace(/\s+/g, " "); }

/**
 * Where a search hits in these messages: ~70 characters around it, or ""
 * with `found` false. `q` is lower-case and trimmed. kuwai-ollama find cuts
 * the same snippet from the files.
 * @param {any[]} messages
 * @param {string} q
 * @returns {{ found: boolean, snippet: string }}
 */
export function searchMessages(messages, q) {
    if (!q) return { found: false, snippet: "" };
    for (const m of messages || []) {
        const t = flat(m);
        const i = t.toLowerCase().indexOf(q);
        if (i >= 0) return { found: true, snippet: (i > 24 ? "…" : "") + t.slice(Math.max(0, i - 24), i + 46) + (i + 46 < t.length ? "…" : "") };
    }
    return { found: false, snippet: "" };
}
