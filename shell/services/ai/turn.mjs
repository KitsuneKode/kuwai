// Folds the agent's events (bin/rice_agent.py) into one assistant message
// made of ordered parts. Pure functions; every change returns new objects,
// because QML only notices a `var` property change by reference.
//
// Qt 6.12's module loader rejects object spread ({...a}): use Object.assign.
//
//   Msg  = { role: "assistant", model, timestamp, status, parts, stats, error }
//   Part = { id, kind: "reasoning"|"text"|"tool"|"steer", itemType, title, input, text,
//            output, status: "running"|"completed"|"failed"|"declined", request,
//            startedAt, endedAt }   (ms, from the events' ts; 0 if unknown)
//   request = null | { id, kind, summary, detail, state: "pending"|"accept"|"decline"|"timeout" }

const KIND = { reasoning: "reasoning", assistant_message: "text", todo_list: "plan" };

export function newAssistant(model, nowMs) {
    return { role: "assistant", model: model, timestamp: nowMs, status: "streaming", parts: [], stats: null, error: "",
        phase: "", startedAt: 0, endedAt: 0 };
}

function withPart(msg, id, change) {
    const i = msg.parts.findIndex(p => p.id === id);
    if (i < 0) return msg;
    const parts = msg.parts.slice();
    parts[i] = Object.assign({}, parts[i], change(parts[i]));
    return Object.assign({}, msg, { parts: parts });
}

function partWithRequest(msg, requestId) {
    return msg.parts.find(p => p.request && p.request.id === requestId);
}

export function applyEvent(msg, ev) {
    if (!ev || !msg) return msg;
    switch (ev.type) {
    case "item.started": {
        const part = {
            id: ev.id, kind: KIND[ev.itemType] || "tool", itemType: ev.itemType, title: ev.title || "",
            input: ev.input || {}, where: ev.where || "", text: "", output: "", status: "running", request: null,
            startedAt: ev.ts || 0, endedAt: 0,
        };
        return Object.assign({}, msg, { parts: msg.parts.concat([part]) });
    }
    case "item.delta":
        return withPart(msg, ev.id, p => ({ text: p.text + (ev.text || "") }));
    case "item.completed":
        return withPart(msg, ev.id, () => ({ status: ev.status || "completed", output: ev.output || "", endedAt: ev.ts || 0 }));
    case "request.opened":
        return withPart(msg, ev.itemId, () => ({
            request: { id: ev.id, kind: ev.kind, summary: ev.summary || "", detail: ev.detail || "",
                options: ev.options || [], state: "pending" },
        }));
    case "request.resolved": {
        const p = partWithRequest(msg, ev.id);
        if (!p) return msg;
        return withPart(msg, p.id, q => ({ request: Object.assign({}, q.request, { state: ev.decision, answer: ev.answer || "" }) }));
    }
    case "turn.steered": {
        const part = { id: ev.id || "steer", kind: "steer", itemType: "user_message", title: "", input: {},
            text: ev.text || "", output: "", status: "completed", request: null, startedAt: ev.ts || 0, endedAt: ev.ts || 0 };
        return Object.assign({}, msg, { parts: msg.parts.concat([part]) });
    }
    case "turn.started":
        return Object.assign({}, msg, { startedAt: ev.ts || msg.startedAt || 0 });
    case "turn.phase":
        return Object.assign({}, msg, { phase: ev.phase || "" });
    case "turn.completed":
        return Object.assign({}, msg, { status: ev.status || "completed", error: ev.error || "", stats: ev.stats || null,
            endedAt: ev.ts || 0, unapplied: ev.unapplied || [] });
    default:
        return msg;
    }
}

export function textOf(msg) {
    if (!msg) return "";
    if (!msg.parts) return msg.text || "";
    return msg.parts.filter(p => p.kind === "text").map(p => p.text).join("\n\n");
}

export function pendingRequest(msg) {
    if (!msg || !msg.parts) return null;
    const p = msg.parts.find(q => q.request && q.request.state === "pending");
    return p ? { id: p.request.id, partId: p.id, kind: p.request.kind, options: p.request.options || [] } : null;
}

// Chats saved before parts: { text, reasoning, tools: [{name, title, state, input, output, errorText}] }.
export function migrateMessage(old) {
    if (!old || old.role !== "assistant" || Array.isArray(old.parts)) return old;
    const parts = [];
    if (old.reasoning) {
        parts.push({ id: "r0", kind: "reasoning", itemType: "reasoning", title: "Thinking", input: {},
            text: old.reasoning, output: "", status: "completed", request: null });
    }
    (old.tools || []).forEach((t, i) => {
        const failed = t.state === "error" || t.state === "output-error" || !!t.errorText;
        parts.push({ id: "t0" + i, kind: "tool", itemType: "dynamic_tool_call", title: t.title || t.name || "Tool",
            input: t.input || {}, text: "", output: failed ? (t.errorText || "") : String(t.output || ""),
            status: failed ? "failed" : "completed", request: null });
    });
    if (old.text) {
        parts.push({ id: "m0", kind: "text", itemType: "assistant_message", title: "", input: {}, text: old.text,
            output: "", status: "completed", request: null });
    }
    return {
        role: "assistant", model: old.model || "", timestamp: old.timestamp || 0, status: "completed", parts: parts,
        stats: old.tokensPerSec ? { tokensPerSec: old.tokensPerSec } : null, error: "",
    };
}

// History for the next request. Earlier tool calls are not replayed: the
// agent's own loop pairs tool calls with results inside a turn.
// `index[i]` is the chat position (plus `offset`) that api[i] came from.
export function toApiMessagesWithIndex(msgs, offset) {
    const api = [], index = [];
    (msgs || []).forEach((m, i) => {
        let e = null;
        if (m.role === "user") {
            e = { role: "user", content: m.text || "" };
            if (m.image) e.image = m.image;
            if (m.context) e.context = m.context;
        } else if (m.role === "assistant") {
            // A steered turn goes back as it happened: assistant, your steer, assistant…
            if (m.parts && m.parts.some(p => p.kind === "steer")) {
                let buf = [];
                const flush = () => { if (buf.length) { api.push({ role: "assistant", content: buf.join("\n\n") }); index.push(i + (offset || 0)); buf = []; } };
                m.parts.forEach(p => {
                    if (p.kind === "text" && p.text) buf.push(p.text);
                    else if (p.kind === "steer") { flush(); api.push({ role: "user", content: p.text }); index.push(i + (offset || 0)); }
                });
                flush();
                return;
            }
            const t = textOf(m);
            if (t) e = { role: "assistant", content: t };
        }
        if (e) { api.push(e); index.push(i + (offset || 0)); }
    });
    return { api: api, index: index };
}

export function toApiMessages(msgs) {
    return toApiMessagesWithIndex(msgs, 0).api;
}

// After the agent compacted and kept the last `kept` api messages, the chat
// position the new summary covers up to (messages before it are summarised).
export function compactedUpTo(upTo, index, kept) {
    const first = index[index.length - kept];
    return first === undefined ? upTo : first;
}

export function truncateAt(msgs, index) {
    return (msgs || []).slice(0, Math.max(0, index));
}

// What a turn's answer rests on, for the Sources row: pages it read first
// (web_fetch), then the top search results it saw; deduped, at most 4.
// [{ url, title, domain, read }]
export function sourcesOf(msg) {
    if (!msg || !msg.parts) return [];
    const read = [], seen = [];
    const domain = u => { const m = /^https?:\/\/([^\/?#]+)/.exec(u); return m ? m[1].replace(/^www\./, "") : u; };
    msg.parts.forEach(p => {
        if (p.kind !== "tool" || p.status !== "completed") return;
        const url = p.input && p.input.url;
        if (url && /^Reading /.test(p.title || "")) {
            read.push({ url: url, title: (p.output || "").split("\n")[0] || domain(url), domain: domain(url), read: true });
        } else if (p.itemType === "web_search") {
            (p.output || "").split("\n").forEach(line => {
                const m = /^\d+\. (.*) — (https?:\/\/\S+)$/.exec(line.trim());
                if (m) seen.push({ url: m[2], title: m[1], domain: domain(m[2]), read: false });
            });
        }
    });
    const out = [];
    read.concat(seen).forEach(s => { if (out.length < 4 && !out.some(o => o.url === s.url)) out.push(s); });
    return out;
}

// An answer's text as prose and fenced code, so code gets its own block
// (language, Copy). A fence still being written comes back `open`.
export function splitFences(text) {
    const out = [];
    const lines = String(text || "").split("\n");
    let md = [], code = null;
    const flushMd = () => { const t = md.join("\n").trim(); if (t) out.push({ kind: "md", text: t }); md = []; };
    lines.forEach(line => {
        const fence = /^\s*```\s*([\w+#.-]*)\s*$/.exec(line);
        if (code === null && fence) { flushMd(); code = { lang: fence[1] || "", lines: [] }; }
        else if (code !== null && /^\s*```\s*$/.test(line)) {
            out.push({ kind: "code", lang: code.lang, text: code.lines.join("\n"), open: false });
            code = null;
        }
        else if (code !== null) code.lines.push(line);
        else md.push(line);
    });
    if (code !== null) out.push({ kind: "code", lang: code.lang, text: code.lines.join("\n"), open: true });
    else flushMd();
    return out;
}

// An answer as render blocks (T3 Code's idea: finished blocks stay put, only
// the last one changes while it streams). Prose splits at blank lines, except
// a list split by blank lines stays one block; code fences are blocks of their
// own (`open` while still being written). Each block's text is stable once
// later text arrives, so its rendered HTML can be cached by text.
const LISTISH = /^\s*([-*+]|\d+[.)])\s/;
export function splitBlocks(text) {
    const out = [];
    splitFences(text).forEach(seg => {
        if (seg.kind === "code") { out.push(seg); return; }
        let cur = [];
        const flush = () => { const t = cur.join("\n").trim(); if (t) out.push({ kind: "md", text: t }); cur = []; };
        const lines = seg.text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.trim() !== "") { cur.push(line); continue; }
            // A blank line: keep going if this is a list and the list carries on.
            let j = i + 1;
            while (j < lines.length && lines[j].trim() === "") j++;
            const inList = cur.some(l => LISTISH.test(l));
            const next = j < lines.length ? lines[j] : "";
            if (inList && (LISTISH.test(next) || /^\s{2,}\S/.test(next))) { cur.push(""); continue; }
            flush();
        }
        flush();
    });
    return out;
}

// Close what a half-written block leaves open (`**bo`, `` `co ``), so the
// live block doesn't flash raw asterisks; the text itself is unchanged.
export function healTail(text) {
    let t = String(text || "");
    const ticks = (t.match(/`/g) || []).length;
    if (ticks % 2 === 1) t += "`";
    const bold = (t.replace(/`[^`]*`/g, "").match(/\*\*/g) || []).length;
    if (bold % 2 === 1) t = t.replace(/\s+$/, "") + "**";
    return t;
}

// A group of tool calls in one line (T3 Code's work-log summaries):
// "Searched 2 times, read 3 pages and ran a command".
export function toolSummary(parts) {
    const n = { search: 0, shop: 0, read: 0, look: 0, run: 0, write: 0, edit: 0, ask: 0, mem: 0, other: 0 };
    (parts || []).forEach(p => {
        const t = p.title || "";
        if (p.itemType === "web_search") n[/^Shopping/.test(t) ? "shop" : "search"]++;
        else if (p.itemType === "command_execution") n.run++;
        else if (p.itemType === "file_change") n[/^Editing /.test(t) ? "edit" : "write"]++;
        else if (/^(Finding|Listing|Searching for) /.test(t)) n.look++;
        else if (/^Remembering/.test(t)) n.mem++;
        else if (p.itemType === "user_input") n.ask++;
        else if (/^Reading /.test(t)) n.read++;
        else n.other++;
    });
    const count = (k, one, many) => n[k] === 1 ? one : n[k] + " " + many;
    const bits = [];
    if (n.search) bits.push(n.search === 1 ? "searched the web" : "searched " + n.search + " times");
    if (n.shop) bits.push(n.shop === 1 ? "checked prices" : "checked prices " + n.shop + " times");
    if (n.read) bits.push("read " + count("read", "a page or file", "pages and files"));
    if (n.look) bits.push(n.look === 1 ? "looked through files" : "searched files " + n.look + " times");
    if (n.write) bits.push("wrote " + count("write", "a file", "files"));
    if (n.edit) bits.push("edited " + count("edit", "a file", "files"));
    if (n.run) bits.push("ran " + count("run", "a command", "commands"));
    if (n.ask) bits.push("asked you");
    if (n.mem) bits.push("saved a memory");
    if (n.other) bits.push("used " + count("other", "a tool", "tools"));
    if (!bits.length) return "";
    const s = bits.length === 1 ? bits[0] : bits.slice(0, -1).join(", ") + " and " + bits[bits.length - 1];
    return s.charAt(0).toUpperCase() + s.slice(1);
}

// The chat as Markdown (Copy chat): what was said, not the tools or reasoning.
export function chatMarkdown(title, msgs) {
    const parts = ["# " + (title || "Chat")];
    (msgs || []).forEach(m => {
        const t = m.role === "user" ? (m.text || "") : textOf(m);
        if (!t) return;
        parts.push("**" + (m.role === "user" ? "You" : "Assistant") + "**", t);
    });
    return parts.join("\n\n") + "\n";
}

