// Folds the agent's events (bin/rice_agent.py) into one assistant message
// made of ordered parts. Pure functions; every change returns new objects,
// because QML only notices a `var` property change by reference.
//
// Qt 6.12's module loader rejects object spread ({...a}): use Object.assign.
//
//   Msg  = { role: "assistant", model, timestamp, status, parts, stats, error }
//   Part = { id, kind: "reasoning"|"text"|"tool", itemType, title, input, text,
//            output, status: "running"|"completed"|"failed"|"declined", request,
//            startedAt, endedAt }   (ms, from the events' ts; 0 if unknown)
//   request = null | { id, kind, summary, detail, state: "pending"|"accept"|"decline"|"timeout" }

const KIND = { reasoning: "reasoning", assistant_message: "text" };

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
            input: ev.input || {}, text: "", output: "", status: "running", request: null,
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
            request: { id: ev.id, kind: ev.kind, summary: ev.summary || "", detail: ev.detail || "", state: "pending" },
        }));
    case "request.resolved": {
        const p = partWithRequest(msg, ev.id);
        if (!p) return msg;
        return withPart(msg, p.id, q => ({ request: Object.assign({}, q.request, { state: ev.decision }) }));
    }
    case "turn.started":
        return Object.assign({}, msg, { startedAt: ev.ts || msg.startedAt || 0 });
    case "turn.phase":
        return Object.assign({}, msg, { phase: ev.phase || "" });
    case "turn.completed":
        return Object.assign({}, msg, { status: ev.status || "completed", error: ev.error || "", stats: ev.stats || null,
            endedAt: ev.ts || 0 });
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
    return p ? { id: p.request.id, partId: p.id } : null;
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
