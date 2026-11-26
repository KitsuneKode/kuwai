// What a T3 Code thread's row says (modules/island/T3Panel), from what
// bin/kuwai-t3 reports about it.
//
// The helper knew more than the panel said. Every thread with something for
// you read "Needs you", whether it wanted a command approved, had asked a
// question or held a guest's message; a thread parked on another thread read
// "Working"; one stopped by a usage limit read "Failed"; and a working thread
// never said for how long. The row now names the state in its own word, at
// the right edge where a glance down the list reads them all, and how long
// it has been so. Resting on a row shows the thread's last reply (the words
// and the preview are t3code-bar's ideas, eliophan/t3code-bar, MIT; no code
// of it is here).
//
// Plain ES for Qt's engine (no lookbehind, no spread, no named groups), typed
// with JSDoc and checked by tsc (tsconfig.check.json). Quickshell reloads on
// QML changes only: after changing this file, save a QML file too.
// @ts-check

/** A thread as bin/kuwai-t3 gives it. @typedef {{ status?: string, ask?: string | null, blocked?: boolean, held?: boolean, limited?: boolean, goal?: boolean, woke?: boolean, at?: string }} Thread */
/** What its row says. `tone`: attention (it wants you), working, idle, caution, error, done. @typedef {{ key: string, word: string, tone: string, timed: boolean }} State */

/**
 * Verified Symbols Nerd Font MDI glyph matching t3code-bar's status iconography.
 * @param {string | null | undefined} key
 * @returns {string}
 */
export function stateGlyph(key) {
    return /** @type {Record<string, string>} */ ({
        approval: "\u{f0499}",
        question: "\u{f0186}",
        input: "\u{f0186}",
        request: "\u{f0013}",
        waiting: "\u{f0625}",
        needs: "\u{f0625}",
        goal: "\u{f04fe}",
        blocked: "\u{f0150}",
        woke: "\u{f0020}",
        failed: "\u{f0028}",
        error: "\u{f0028}",
        limited: "\u{f051f}",
        done: "\u{f05e0}",
        working: "\u{f0772}",
        starting: "\u{f0772}"
    })[String(key || "")] || "";
}

/**
 * The thread's state in one word. `timed`: the word is followed by how long
 * (working for 8m, done 2h ago); a thread that wants you is not, it wants you now.
 * @param {Thread | null | undefined} t @returns {State}
 */
export function stateOf(t) {
    const s = t && t.status || "";
    if (s === "waiting") {
        const ask = t && t.ask;
        return ask === "approval" ? { key: "approval", word: "Approval", tone: "attention", timed: false }
            : (ask === "question" || ask === "input") ? { key: "question", word: "Question", tone: "attention", timed: false }
            : ask === "request" ? { key: "request", word: "Request", tone: "attention", timed: false }
            : { key: "waiting", word: "Needs you", tone: "attention", timed: false };
    }
    if (s === "woke" || (t && t.woke)) return { key: "woke", word: "Woke", tone: "attention", timed: false };
    if (s === "failed") return t && t.limited ? { key: "limited", word: "Limit reached", tone: "caution", timed: true }
        : { key: "failed", word: "Failed", tone: "error", timed: true };
    if (s === "completed") return { key: "done", word: "Done", tone: "done", timed: true };
    if (s === "goal" || (s === "running" && t && t.goal)) return { key: "goal", word: "Goal", tone: "working", timed: true };
    if (s === "running") return t && t.blocked ? { key: "blocked", word: "Waiting", tone: "idle", timed: false }
        : { key: "working", word: "Working", tone: "working", timed: true };
    return { key: "starting", word: "Starting", tone: "working", timed: false };
}

/**
 * What the island's T3 capsule says: the one state that matters most, as a
 * word, and how many threads share it (t3code-bar's idea: say what's wanted,
 * not how many there are). Wants you (Approval, Question, Request, Needs you)
 * > stopped at a limit > failed > working. Finished threads aren't news here
 * (the capsule's ✓ counts those); nothing going on: null.
 * When several want you for different reasons it says "Needs you".
 * @param {Thread[]} items @returns {{ key: string, word: string, tone: string, count: number } | null}
 */
export function headline(items) {
    const list = (items || []).map(t => ({ t, st: stateOf(t) }));
    /** @param {string[]} keys */
    const pick = (keys) => list.filter(x => keys.includes(x.st.key));
    const want = pick(["approval", "question", "request", "waiting"]);
    if (want.length) {
        const kinds = new Set(want.map(x => x.st.key));
        const st = kinds.size === 1 ? want[0].st : { key: "waiting", word: "Needs you", tone: "attention" };
        return { key: st.key, word: st.word, tone: st.tone, count: want.length };
    }
    for (const keys of [["limited"], ["failed"], ["working", "starting"]]) {
        const got = pick(keys);
        if (got.length) {
            const lead = got.find(x => x.st.key === keys[0]) || got[0];
            return { key: lead.st.key, word: lead.st.word, tone: lead.st.tone, count: got.length };
        }
    }
    return null;
}

/** The same, for a screen reader: what the word stands for. @param {Thread | null | undefined} t */
export function spoken(t) {
    return ({ approval: "Wants your approval", question: "Has a question for you", request: "A guest wrote to it",
              waiting: "Needs you", woke: "Scheduled task woke up", limited: "Stopped at a usage limit", failed: "Failed", done: "Finished",
              blocked: t && t.held ? "Waiting on background work" : "Waiting on another thread", goal: "Working on a goal", working: "Working", starting: "Starting" })[stateOf(t).key];
}

/**
 * How long, short: "now", "8m", "2h", "3d". "" when the time can't be read
 * (the row then says the word alone; it said "NaN h ago" once).
 * @param {string | number | null | undefined} at @param {number} now
 */
export function since(at, now) {
    const t = typeof at === "number" ? at : Date.parse(String(at || ""));
    if (!isFinite(t)) return "";
    const m = Math.max(0, Math.floor((now - t) / 60000));
    return m < 1 ? "now" : m < 60 ? m + "m" : m < 1440 ? Math.floor(m / 60) + "h" : Math.floor(m / 1440) + "d";
}

/**
 * A reply as a few plain lines for the preview: code blocks dropped, a link
 * as its label, heading marks, quote marks and emphasis removed, a bullet as
 * "• ". Five lines and 360 characters at most, cut at a word, "…" when cut.
 * @param {unknown} markdown @returns {string}
 */
export function excerpt(markdown) {
    const text = String(markdown || "")
        .replace(/```[\s\S]*?(?:```|$)/g, "")
        .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1");
    const lines = [];
    const raw = text.split("\n");
    for (let i = 0; i < raw.length; i++) {
        const s = raw[i].trim()
            .replace(/^#{1,6}\s+/, "")
            .replace(/^>\s?/, "")
            .replace(/^[-*]\s+/, "• ")
            .replace(/\*\*|__|`/g, "")
            .trim();
        if (s !== "" && !/^[-=*_]{3,}$/.test(s)) lines.push(s);
    }
    let cut = lines.length > 5;
    let out = lines.slice(0, 5).join("\n");
    const chars = Array.from(out);
    if (chars.length > 360) {
        const head = chars.slice(0, 360).join("");
        const at = head.lastIndexOf(" ");
        out = at > 0 ? head.slice(0, at) : head;
        cut = true;
    }
    return cut ? out.replace(/[\s.,;:]+$/, "") + "…" : out;
}
