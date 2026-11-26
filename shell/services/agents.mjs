// @ts-check
import { stateOf, stateGlyph } from "./t3.mjs";

/**
 * A kitty pane, as the caller reads it from Kittymux.running.
 * @typedef {{ key?: string, agent?: string, title?: string, state?: string, needs?: boolean, working?: boolean,
 *   ask?: boolean, since?: number, limitReset?: number, account?: string, event?: string, action?: any,
 *   pid?: number | string, w?: string, where?: string, question?: string, raw?: any }} Pane
 */
/** An unread kittymux event. @typedef {{ id: string, kind?: string, severity?: string, agent?: string, t?: number }} Event */
/** A T3 thread (bin/kuwai-t3). @typedef {{ thread?: string, title?: string, status?: string, ask?: string | null, limited?: boolean, blocked?: boolean, goal?: boolean, woke?: boolean, held?: boolean, at?: string, provider?: string, request?: { prompt?: string } | null }} Thread */
/** A Desktop agent hook session (bin/kuwai-agent-hook). @typedef {{ id?: string, agent?: string, state?: string, ask?: string | null, title?: string, project?: string, cwd?: string, model?: string, question?: string, window_class?: string, since?: number, updated_at?: number, pane?: string, thread?: string }} Desktop */
/** One agent, any surface (kitty TUI, t3, desktop). @typedef {{ src: string, agent: string, key: string, stateKey: string, glyph: string, word: string, rank: number, t: number, reset: number, account: string, title: string, event: string, action: any, thread: string, windowClass: string, desktopId: string }} Item */
/**
 * One real agent session, however many surfaces report it: `key` is its
 * canonical identity (the kitty pane, the T3 thread, else the hook session),
 * `sources` every surface that named it, `src` the one a click goes through.
 * @typedef {Item & { state: string, section: string, sources: string[], question: string, pane: Pane | null, t3: Thread | null, hook: Desktop | null }} Session
 */

/** T3's provider names → kittymux's agent names (its brand marks). @param {string | undefined} p */
export function t3Agent(p) {
    const base = String(p || "").replace(/^acpRegistry_/, "").replace(/_(\d+|personal|work|main)$/, "");
    const known = /** @type {Record<string, string>} */ ({ claudeAgent: "claude", codex: "codex", cursor: "cursor", antigravity: "antigravity",
        opencode: "opencode", gemini: "gemini", grok: "grok", devin: "devin", kiro: "kiro" });
    return known[base] || known[base.split("_")[0]] || base;
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
        : rank === FAILED ? "failed" : rank === LIMITED ? "limited" : rank === WORKING ? "working" : st === "done" ? "done" : "";
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
    return ranked(sessions(panes, threads, desktop));
}

/** The sessions that matter now, most urgent first, the longest waiting first within a state. @param {Session[]} list @returns {Session[]} */
export function ranked(list) {
    return list.filter(x => x.rank !== OTHER).sort((a, b) => (a.rank - b.rank) || ((a.t || Infinity) - (b.t || Infinity)));
}

const PANE = /^w\d+\.\d+$/;

/** A kitty pane's own key, "w<kitty pid>.<window id>", as kittymux and the hook both write it. @param {Pane | null | undefined} p */
export function paneKey(p) {
    const k = String(p && p.key || "");
    if (PANE.test(k)) return k;
    return p && p.pid && p.w ? "w" + p.pid + "." + p.w : "";
}

/**
 * The canonical identity of what a surface reports: its kitty pane, its T3
 * thread, else its hook session.
 * @param {string} src @param {Pane | Thread | Desktop} r @returns {string}
 */
export function identity(src, r) {
    const x = /** @type {Record<string, any>} */ (r || {});
    if (src === "t3") return "t3:" + String(x.thread || "");
    if (src === "kitty") { const k = paneKey(x); return k ? "pane:" + k : "kitty:" + String(x.key || ""); }
    if (x.thread) return "t3:" + String(x.thread);
    if (x.pane && PANE.test(String(x.pane))) return "pane:" + x.pane;
    return "hook:" + String(x.id || "");
}

/** @param {string | undefined} p @param {string} home */
function dir(p, home) { return String(p || "").replace(/^~(?=\/|$)/, home || "~").replace(/\/+$/, ""); }

const STATES = ["needs", "error", "limited", "working", "done", "idle"];
const SECTIONS = /** @type {Record<string, string>} */ ({ kitty: "Terminal", t3: "T3 Code", desktop: "Desktop" });
const LEAD = /** @type {Record<string, number>} */ ({ kitty: 0, t3: 1, desktop: 2 });

/** @param {Item} it @returns {string} */
function stateOfItem(it) {
    return it.rank === WANTS ? "needs" : it.rank === FAILED ? "error" : it.rank === LIMITED ? "limited"
        : it.rank === WORKING ? "working" : it.stateKey === "done" ? "done" : "idle";
}

/**
 * Every real agent session once. A hook session inside a kitty pane (the
 * pane it names, or the one pane of that agent in its folder), a thread T3
 * lists twice, a pane kittymux lists twice: one session, whose state is the
 * most urgent any surface reports and whose click goes through the surface
 * that can take you there (the pane, then the thread, then the window).
 * @param {Pane[]} panes @param {Thread[]} threads @param {Desktop[]} [desktop] @param {{ home?: string }} [opts]
 * @returns {Session[]}
 */
export function sessions(panes, threads, desktop, opts) {
    const home = opts && opts.home || "";
    /** @type {{ id: string, it: Item, rec: any }[]} */
    const all = [];
    for (const p of panes || []) all.push({ id: identity("kitty", p), it: fromPane(p), rec: p });
    for (const t of threads || []) all.push({ id: identity("t3", t), it: fromThread(t), rec: t });
    for (const d of desktop || []) {
        let id = identity("desktop", d);
        if (id.startsWith("hook:") && !d.pane && d.cwd) {
            const at = dir(d.cwd, home), who = providerId(d.agent || "");
            const same = (panes || []).filter(p => providerId(p.agent || "") === who && at !== "" && dir(p.where, home) === at);
            if (same.length === 1) id = identity("kitty", same[0]);
        }
        all.push({ id, it: fromDesktop(d), rec: d });
    }
    /** @type {Record<string, { id: string, it: Item, rec: any }[]>} */
    const by = {};
    /** @type {string[]} */
    const order = [];
    for (const x of all) {
        if (!by[x.id]) { by[x.id] = []; order.push(x.id); }
        by[x.id].push(x);
    }
    return order.map(id => {
        const group = by[id];
        const lead = group.slice().sort((a, b) => LEAD[a.it.src] - LEAD[b.it.src])[0];
        const hot = group.slice().sort((a, b) => STATES.indexOf(stateOfItem(a.it)) - STATES.indexOf(stateOfItem(b.it))
            || LEAD[a.it.src] - LEAD[b.it.src])[0];
        /** @param {string} src */
        const of = src => { const g = group.find(x => x.it.src === src); return g ? g.rec : null; };
        const pane = of("kitty"), t3 = of("t3"), hook = of("desktop");
        const kitty = group.find(x => x.it.src === "kitty");
        const desk = group.find(x => x.it.src === "desktop");
        return Object.assign({}, lead.it, {
            key: id, stateKey: hot.it.stateKey, glyph: hot.it.glyph, word: hot.it.word, rank: hot.it.rank, t: hot.it.t || lead.it.t,
            reset: Math.max(...group.map(x => x.it.reset || 0)),
            title: lead.it.title || hot.it.title,
            event: kitty ? kitty.it.event : "", action: kitty ? kitty.it.action : lead.it.action,
            thread: t3 ? String(t3.thread || "") : lead.it.thread,
            windowClass: desk ? desk.it.windowClass : "", desktopId: desk ? desk.it.desktopId : "",
            state: stateOfItem(hot.it), section: SECTIONS[lead.it.src] || "",
            sources: [...new Set(group.map(x => x.it.src))],
            question: String(hot.rec.question || (t3 && t3.request && t3.request.prompt) || (hook && hook.question) || (pane && pane.question) || ""),
            pane, t3, hook
        });
    });
}

/**
 * How many sessions are in each state, in each section and from each surface:
 * the one tally the header, the capsule and the stack all read.
 * @param {Session[]} list
 * @returns {{ total: number, needs: number, working: number, error: number, limited: number, done: number, idle: number, bySection: Record<string, number>, bySource: { t3: number, tui: number, desktop: number } }}
 */
export function counts(list) {
    /** @param {string} st */
    const n = st => list.filter(x => x.state === st).length;
    /** @type {Record<string, number>} */
    const bySection = {};
    for (const x of list) bySection[x.section] = (bySection[x.section] || 0) + 1;
    const live = list.filter(x => x.state === "needs" || x.state === "working");
    return {
        total: list.length, needs: n("needs"), working: n("working"), error: n("error"), limited: n("limited"), done: n("done"), idle: n("idle"),
        bySection,
        bySource: { t3: live.filter(x => x.src === "t3").length, tui: live.filter(x => x.src === "kitty").length, desktop: live.filter(x => x.src === "desktop").length }
    };
}

/**
 * The capsule's stack: the sessions that need you, then the ones working, each
 * surface in turn (kitty, T3, desktop), with what the marks and the tip need.
 * @param {Session[]} list @param {string} [only] "needs" or "work"
 * @returns {(Session & { needs: boolean, status: string, where: string })[]}
 */
export function stackList(list, only) {
    const live = list.filter(x => x.state === "needs" || x.state === "working")
        .sort((a, b) => Number(b.state === "needs") - Number(a.state === "needs") || LEAD[a.src] - LEAD[b.src]);
    const out = live.map(x => Object.assign({}, x, {
        needs: x.state === "needs", status: x.state === "needs" ? "needs you" : "working",
        where: x.src === "t3" ? "T3" : x.src === "desktop" ? "Desktop" : "TUI"
    }));
    return only === "needs" ? out.filter(x => x.needs) : only === "work" ? out.filter(x => !x.needs) : out;
}

/**
 * Session-reported limits (kittymux panes, T3 threads, desktop hooks) for the
 * right-side limit pills so limits never hijack active work on the left.
 * @param {Pane[]} panes @param {Thread[]} threads @param {Desktop[]} [desktop] @returns {Item[]}
 */
export function limitedItems(panes, threads, desktop) {
    return limitedOf(sessions(panes, threads, desktop));
}

/** @param {Session[]} list @returns {Item[]} */
export function limitedOf(list) {
    return ranked(list)
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
    return headlineOf(sessions(panes, threads, desktop), doneKitty, doneT3, doneDesktop);
}

/**
 * The same, from sessions already made.
 * @param {Session[]} sessionList @param {number} doneKitty @param {number} doneT3 @param {number} [doneDesktop]
 * @returns {{ word: string, glyph: string, stateKey: string, tone: string, count: number, working: number, done: number, limited: number, key: string, bySource: { t3: number, tui: number, desktop: number } }}
 */
export function headlineOf(sessionList, doneKitty, doneT3, doneDesktop) {
    const all = ranked(sessionList);
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
    return targetOf(sessions(panes, threads, desktop));
}

/** @param {Session[]} list @returns {Session | null} */
export function targetOf(list) {
    return ranked(list).find(x => x.rank < WORKING) || null;
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
