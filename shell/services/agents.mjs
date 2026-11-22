// @ts-check
import { stateOf } from "./t3.mjs";

/**
 * A kitty pane, as the caller reads it from Kittymux.running.
 * @typedef {{ key?: string, agent?: string, title?: string, state?: string, needs?: boolean, working?: boolean,
 *   ask?: boolean, since?: number, limitReset?: number, event?: string, action?: any }} Pane
 */
/** An unread kittymux event. @typedef {{ id: string, kind?: string, severity?: string, agent?: string, t?: number }} Event */
/** A T3 thread (bin/kuwai-t3). @typedef {{ thread?: string, title?: string, status?: string, ask?: string | null, limited?: boolean, blocked?: boolean, at?: string, provider?: string }} Thread */
/** One agent, either kind. @typedef {{ src: string, agent: string, key: string, word: string, rank: number, t: number, reset: number, title: string, event: string, action: any, thread: string }} Item */

/** T3's provider names → kittymux's agent names (its brand marks). @param {string | undefined} p */
export function t3Agent(p) {
    const base = String(p || "").replace(/_\d+$/, "");
    return /** @type {Record<string, string>} */ ({ claudeAgent: "claude", codex: "codex", cursor: "cursor", antigravity: "antigravity",
        opencode: "opencode", gemini: "gemini", grok: "grok" })[base] || base;
}

const WANTS = 0, FAILED = 1, LIMITED = 2, WORKING = 3, OTHER = 9;

/** @param {Pane} r @returns {Item} */
function fromPane(r) {
    const st = r.state || "";
    const rank = r.needs || st === "waiting" ? WANTS : st === "error" ? FAILED : st === "limited" ? LIMITED
        : r.working || st === "working" ? WORKING : OTHER;
    return {
        src: "kitty", agent: String(r.agent || ""), key: "k" + (r.key || ""), title: String(r.title || ""),
        word: rank === WANTS ? (r.ask ? "Approval" : "Needs you") : rank === FAILED ? "Failed" : rank === LIMITED ? "Limit reached" : "",
        rank, t: (r.since || 0) * 1000, reset: (r.limitReset || 0) * 1000,
        event: String(r.event || ""), action: r.action, thread: ""
    };
}

/** @param {Thread} i @returns {Item} */
function fromThread(i) {
    const st = stateOf(i);
    const rank = st.tone === "attention" ? WANTS : st.key === "failed" ? FAILED : st.key === "limited" ? LIMITED
        : st.key === "working" || st.key === "starting" ? WORKING : OTHER;
    const t = Date.parse(String(i.at || ""));
    return {
        src: "t3", agent: t3Agent(i.provider), key: "t" + (i.thread || ""), title: String(i.title || ""),
        word: rank === WORKING || rank === OTHER ? "" : st.word,
        rank, t: isFinite(t) ? t : 0, reset: 0, event: "", action: null, thread: String(i.thread || "")
    };
}

/**
 * Both lists as one, the one that wants you most first; within a state the
 * one that has waited longest first (it asked before the others).
 * @param {Pane[]} panes @param {Thread[]} threads @returns {Item[]}
 */
export function merge(panes, threads) {
    const all = (panes || []).map(fromPane).concat((threads || []).map(fromThread));
    return all.filter(x => x.rank !== OTHER).sort((a, b) => (a.rank - b.rank) || ((a.t || Infinity) - (b.t || Infinity)));
}

/** "41m", "2h 5m": how long until a time (ms). "" when unknown or past. @param {number} at @param {number} now */
export function until(at, now) {
    if (!at || at <= now) return "";
    const mins = Math.max(1, Math.round((at - now) / 60000));
    const h = Math.floor(mins / 60), m = mins % 60;
    return h ? h + "h" + (m ? " " + m + "m" : "") : m + "m";
}

/**
 * What the one capsule says. `word` the state that wants you most ("Approval",
 * "Question 2", "Needs you" when several want different things, "Failed",
 * "Back in 41m" when a limit says when it ends, else "Limit reached"); ""
 * while they only work (the capsule shows the working count in its ring).
 * `tone`: attention, error, caution, working, or "" with nothing going on.
 * `done`: finished and not yet seen, both kinds.
 * @param {Pane[]} panes @param {Thread[]} threads @param {number} doneKitty @param {number} doneT3 @param {number} now
 * @returns {{ word: string, tone: string, count: number, working: number, done: number, key: string }}
 */
export function headline(panes, threads, doneKitty, doneT3, now) {
    const list = merge(panes, threads);
    const working = list.filter(x => x.rank === WORKING).length;
    const done = Math.max(0, doneKitty || 0) + Math.max(0, doneT3 || 0);
    const top = list[0];
    if (!top || top.rank === WORKING)
        return { word: "", tone: working ? "working" : done ? "done" : "", count: working, working, done, key: working ? "working" : done ? "done" : "" };
    const same = list.filter(x => x.rank === top.rank);
    if (top.rank === WANTS) {
        const kinds = new Set(same.map(x => x.word));
        const word = kinds.size === 1 ? top.word : "Needs you";
        return { word: word + (same.length > 1 ? " " + same.length : ""), tone: "attention", count: same.length, working, done, key: "wants:" + word };
    }
    if (top.rank === FAILED)
        return { word: "Failed" + (same.length > 1 ? " " + same.length : ""), tone: "error", count: same.length, working, done, key: "failed" };
    const resets = same.map(x => x.reset).filter(r => r > now).sort((a, b) => a - b);
    const back = resets.length ? until(resets[0], now) : "";
    return { word: back ? "Back in " + back : "Limit reached", tone: "caution", count: same.length, working, done, key: "limited" };
}

/**
 * Where "go to what needs me" goes: the agent that wants you and has waited
 * longest, else one that failed, else one stopped at a limit. Nothing asking:
 * null (the caller opens the list instead). A working agent is never the
 * answer: it doesn't need you.
 * @param {Pane[]} panes @param {Thread[]} threads @returns {Item | null}
 */
export function target(panes, threads) {
    const top = merge(panes, threads)[0];
    return top && top.rank < WORKING ? top : null;
}
