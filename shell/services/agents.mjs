// @ts-check
import { stateOf, stateGlyph } from "./t3.mjs";

/**
 * A kitty pane, as the caller reads it from Kittymux.running.
 * @typedef {{ key?: string, agent?: string, title?: string, state?: string, needs?: boolean, working?: boolean,
 *   ask?: boolean, since?: number, limitReset?: number, account?: string, event?: string, action?: any }} Pane
 */
/** An unread kittymux event. @typedef {{ id: string, kind?: string, severity?: string, agent?: string, t?: number }} Event */
/** A T3 thread (bin/kuwai-t3). @typedef {{ thread?: string, title?: string, status?: string, ask?: string | null, limited?: boolean, blocked?: boolean, goal?: boolean, woke?: boolean, at?: string, provider?: string }} Thread */
/** A Desktop agent hook session (bin/kuwai-agent-hook). @typedef {{ id?: string, agent?: string, state?: string, ask?: string | null, title?: string, project?: string, cwd?: string, model?: string, question?: string, window_class?: string, since?: number, updated_at?: number }} Desktop */
/** One agent, any surface (kitty TUI, t3, desktop). @typedef {{ src: string, agent: string, key: string, stateKey: string, glyph: string, word: string, rank: number, t: number, reset: number, account: string, title: string, event: string, action: any, thread: string, windowClass: string, desktopId: string }} Item */

/** T3's provider names → kittymux's agent names (its brand marks). @param {string | undefined} p */
export function t3Agent(p) {
    const base = String(p || "").replace(/^acpRegistry_/, "").replace(/_(\d+|personal|work|main)$/, "");
    return /** @type {Record<string, string>} */ ({ claudeAgent: "claude", codex: "codex", cursor: "cursor", antigravity: "antigravity",
        opencode: "opencode", gemini: "gemini", grok: "grok", devin: "devin" })[base] || base;
}

/**
 * One id per provider whichever source names it: kittymux says agy and
 * cursor-agent, T3 says antigravity and cursor (limits dedupe and the Usage
 * tabs key on this).
 * @param {string} name @returns {string}
 */
export function providerId(name) {
    const s = t3Agent(String(name || "")).toLowerCase();
    return /** @type {Record<string, string>} */ ({ agy: "antigravity", "cursor-agent": "cursor", "claude-code": "claude", claudeagent: "claude" })[s] || s;
}

export { stateGlyph };

const WANTS = 0, FAILED = 1, WORKING = 2, LIMITED = 3, OTHER = 9;

/** @param {Pane} r @returns {Item} */
function fromPane(r) {
    const st = r.state || "";
    const rank = r.needs || st === "waiting" ? WANTS : st === "error" ? FAILED : st === "limited" ? LIMITED
        : r.working || st === "working" ? WORKING : OTHER;
    const stateKey = rank === WANTS ? (r.ask ? "approval" : "waiting")
        : rank === FAILED ? "failed" : rank === LIMITED ? "limited" : rank === WORKING ? "working" : "";
    return {
        src: "kitty", agent: String(r.agent || ""), key: "k" + (r.key || ""), stateKey, glyph: stateGlyph(stateKey), title: String(r.title || ""),
        word: rank === WANTS ? (r.ask ? "Approval" : "Needs you") : rank === FAILED ? "Failed" : rank === LIMITED ? "Limit reached" : "",
        rank, t: (r.since || 0) * 1000, reset: (r.limitReset || 0) * 1000, account: String(r.account || ""),
        event: String(r.event || ""), action: r.action, thread: "", windowClass: "", desktopId: ""
    };
}

/** @param {Thread} i @returns {Item} */
function fromThread(i) {
    const st = stateOf(i);
    const rank = st.tone === "attention" ? WANTS : st.key === "failed" ? FAILED : st.key === "limited" ? LIMITED
        : st.key === "working" || st.key === "starting" || st.key === "goal" ? WORKING : OTHER;
    const t = Date.parse(String(i.at || ""));
    return {
        src: "t3", agent: t3Agent(i.provider), key: "t" + (i.thread || ""), stateKey: st.key, glyph: stateGlyph(st.key), title: String(i.title || ""),
        word: rank === WORKING || rank === OTHER ? "" : st.word,
        rank, t: isFinite(t) ? t : 0, reset: 0, account: "", event: "", action: null, thread: String(i.thread || ""), windowClass: "", desktopId: ""
    };
}

/** @param {Desktop} d @returns {Item} */
function fromDesktop(d) {
    const st = String(d && d.state || "");
    const ask = d && d.ask || null;
    const stateKey = st === "waiting" ? (ask === "approval" ? "approval" : (ask === "question" || ask === "input") ? "question" : ask === "request" ? "request" : "waiting")
        : st === "woke" ? "woke" : st === "failed" ? "failed" : st === "limited" ? "limited"
        : st === "goal" ? "goal" : st === "working" ? "working" : st === "blocked" ? "blocked" : st === "done" ? "done" : "";
    const rank = stateKey === "approval" || stateKey === "question" || stateKey === "request" || stateKey === "waiting" || stateKey === "woke" ? WANTS
        : stateKey === "failed" ? FAILED : stateKey === "limited" ? LIMITED
        : stateKey === "working" || stateKey === "goal" ? WORKING : OTHER;
    const word = stateKey === "approval" ? "Approval" : stateKey === "question" ? "Question" : stateKey === "request" ? "Request"
        : stateKey === "waiting" ? "Needs you" : stateKey === "woke" ? "Woke" : stateKey === "failed" ? "Failed"
        : stateKey === "limited" ? "Limit reached" : "";
    return {
        src: "desktop", agent: String(d.agent || "desktop"), key: "d" + (d.id || ""), stateKey, glyph: stateGlyph(stateKey), title: String(d.title || ""),
        word, rank, t: (d.since || d.updated_at || 0) * 1000, reset: 0, account: "",
        event: "", action: null, thread: "", windowClass: String(d.window_class || ""), desktopId: String(d.id || "")
    };
}

/**
 * All active surfaces as one, the one that wants you most first; within a state
 * the one that has waited longest first (it asked before the others).
 * @param {Pane[]} panes @param {Thread[]} threads @param {Desktop[]} [desktop] @returns {Item[]}
 */
export function merge(panes, threads, desktop) {
    const all = (panes || []).map(fromPane).concat((threads || []).map(fromThread), (desktop || []).map(fromDesktop));
    return all.filter(x => x.rank !== OTHER).sort((a, b) => (a.rank - b.rank) || ((a.t || Infinity) - (b.t || Infinity)));
}

/**
 * Session-reported limits (kittymux panes, T3 threads, desktop hooks) for the
 * right-side limit pills so limits never hijack active work on the left.
 * @param {Pane[]} panes @param {Thread[]} threads @param {Desktop[]} [desktop] @returns {Item[]}
 */
export function limitedItems(panes, threads, desktop) {
    return merge(panes, threads, desktop)
        .filter(x => x.rank === LIMITED)
        .sort((a, b) => ((a.reset || Infinity) - (b.reset || Infinity)) || ((a.t || Infinity) - (b.t || Infinity)));
}

/** "41m", "2h 5m": how long until a time (ms). "" when unknown or past. @param {number} at @param {number} now */
export function until(at, now) {
    if (!at || at <= now) return "";
    const mins = Math.max(1, Math.round((at - now) / 60000));
    const h = Math.floor(mins / 60), m = mins % 60;
    return h ? h + "h" + (m ? " " + m + "m" : "") : m + "m";
}

/**
 * What the left Agents capsule says. Limits are handled by the dedicated
 * right-side limit pills and never hijack active work here.
 * @param {Pane[]} panes @param {Thread[]} threads @param {number} doneKitty @param {number} doneT3 @param {number} now @param {Desktop[]} [desktop] @param {number} [doneDesktop]
 * @returns {{ word: string, glyph: string, stateKey: string, tone: string, count: number, working: number, done: number, limited: number, key: string, bySource: { t3: number, tui: number, desktop: number } }}
 */
export function headline(panes, threads, doneKitty, doneT3, now, desktop, doneDesktop) {
    const all = merge(panes, threads, desktop);
    const list = all.filter(x => x.rank !== LIMITED);
    const limited = all.length - list.length;
    const working = list.filter(x => x.rank === WORKING).length;
    const done = Math.max(0, doneKitty || 0) + Math.max(0, doneT3 || 0) + Math.max(0, doneDesktop || 0);
    const bySource = {
        t3: list.filter(x => x.src === "t3").length,
        tui: list.filter(x => x.src === "kitty").length,
        desktop: list.filter(x => x.src === "desktop").length
    };
    const top = list[0];
    if (!top || top.rank === WORKING) {
        const goal = top && list.some(x => x.stateKey === "goal");
        return {
            word: "", glyph: working ? stateGlyph(goal ? "goal" : "working") : done ? stateGlyph("done") : "",
            stateKey: working ? (goal ? "goal" : "working") : done ? "done" : "",
            tone: working ? "working" : done ? "done" : "", count: working, working, done, limited,
            key: working ? (goal ? "goal" : "working") : done ? "done" : "", bySource
        };
    }
    const same = list.filter(x => x.rank === top.rank);
    if (top.rank === WANTS) {
        const kinds = new Set(same.map(x => x.word));
        const word = kinds.size === 1 ? top.word : "Needs you";
        const stateKey = kinds.size === 1 ? top.stateKey : "waiting";
        return {
            word: word + (same.length > 1 ? " " + same.length : ""),
            glyph: stateGlyph(stateKey), stateKey, tone: "attention", count: same.length, working, done, limited,
            key: "wants:" + word, bySource
        };
    }
    return {
        word: "Failed" + (same.length > 1 ? " " + same.length : ""),
        glyph: stateGlyph("failed"), stateKey: "failed", tone: "error", count: same.length, working, done, limited,
        key: "failed", bySource
    };
}

/**
 * Where "go to what needs me" goes: the agent that wants you and has waited
 * longest, else one that failed. Working and limited agents are not jumps.
 * @param {Pane[]} panes @param {Thread[]} threads @param {Desktop[]} [desktop] @returns {Item | null}
 */
export function target(panes, threads, desktop) {
    const top = merge(panes, threads, desktop).find(x => x.rank < WORKING);
    return top || null;
}

/**
 * The capsule's marks: each provider once, the one that wants you first, with
 * how many of its agents are active and whether any of them needs you.
 * @param {{ agent?: string, needs?: boolean }[]} list @param {number} max
 * @returns {{ marks: { agent: string, count: number, needs: boolean }[], more: number }}
 */
export function stackMarks(list, max) {
    /** @type {Record<string, { agent: string, count: number, needs: boolean }>} */
    const by = {};
    /** @type {{ agent: string, count: number, needs: boolean }[]} */
    const all = [];
    for (const a of list || []) {
        const k = String(a.agent || "agent");
        if (!by[k]) all.push(by[k] = { agent: k, count: 0, needs: false });
        by[k].count++;
        if (a.needs) by[k].needs = true;
    }
    all.sort((a, b) => Number(b.needs) - Number(a.needs));
    return { marks: all.slice(0, max), more: Math.max(0, all.length - max) };
}
