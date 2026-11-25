pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.config
import qs.services
import "ai/turn.mjs" as Turn
// Quickshell reloads on QML changes, not on the modules they import: after
// changing chatstore.mjs or caches.mjs, save this file too (or restart).
import "ai/chatstore.mjs" as ChatStore
import "caches.mjs" as Caches

// The assistant's state. Turns run in bin/kuwai_agent.py (`kuwai-ollama agent`),
// which prints events; Turn.applyEvent folds them into `draft`, an assistant
// message made of parts (reasoning, tools, text). See
// docs/superpowers/plans/2026-11-03-assistant-agent-parity.md.
Singleton {
    id: root

    readonly property string bin: Paths.bin + "/kuwai-ollama"     // the running channel's copy, not the dev checkout
    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID"))) + "/kuwai/ai"
    readonly property string reqPath: runtimeDir + "/request.json"

    property string status: "offline" // "ready" | "loading" | "offline"
    property string model: "qwen3.5:4b"
    // Chat (answers, search, prices, what's on screen; reads, never changes) or Agent (files,
    // sandbox, plans, your machine with approval). Saved per chat; a new chat keeps the last one.
    property string mode: "chat"
    property var availableModels: ["qwen3.5:4b"]
    property var runningModels: []
    // From `kuwai-ollama status`: { name: { capabilities: [...], sizeGb, params } }.
    property var modelInfo: ({})

    function hasCap(m, cap) {
        const i = modelInfo[m];
        return !!i && (i.capabilities || []).indexOf(cap) >= 0;
    }
    function isLoaded(m) { return runningModels.some(r => r.name === m); }
    property bool streaming: false
    // A turn belongs to the chat that asked (draftSessionId). Switching chats
    // or starting a new one leaves it running there: it used to be thrown
    // away (abandon()), so the answer never came. The views read these:
    // what's generating *here*, and its live draft.
    readonly property bool busyHere: streaming && !discardDraft && draftSessionId === activeSessionId
    readonly property var draftHere: busyHere ? draft : null
    readonly property var pendingHere: busyHere ? pendingRequest : null
    // Chats with an answer that arrived while you were elsewhere (a dot in the list).
    property var unread: ({})

    // The assistant message being streamed (Turn.newAssistant shape), or null.
    property var draft: null
    // Drop the draft when the turn ends (new chat / switch / clear mid-turn).
    property bool discardDraft: false
    property string draftSessionId: ""

    readonly property var pendingRequest: discardDraft ? null : Turn.pendingRequest(draft)

    // Snapshot context the next message carries: {app, title, workspace, cwd, git, selection, clipboard} or null.
    property var pendingContext: null
    property string pendingAppTitle: ""
    property string pendingImage: ""
    property var lastStats: null
    property string errorText: ""

    // Active session messages. User: { role, text, image, context, time, timestamp, model }.
    // Assistant: Turn's Msg ({ role, model, timestamp, status, parts, stats, error }) plus the
    // older flat fields (text, html, reasoning, tools, time, tokensPerSec) the renderer still reads.
    property var messages: []
    // The chat list, metadata only (ChatStore's Meta): [{ id, title, renamed, model, mode,
    // updatedAt, count }]. Messages live one chat to a file (ai-chats/<id>.json) and only
    // the open chat's are in memory (`messages`, `summary`), plus a chat a turn is still
    // answering in after you left it (`held`). Everything else is read when it's opened.
    property var sessions: []
    property string activeSessionId: ""
    // id → { messages, summary, summaryUpTo }: chats other than the open one that a turn
    // needs (it's answering there, or a queued message started it). Released when it ends.
    property var held: ({})
    // Chats whose file is behind what's in memory (id → true), and whether the list is.
    property var dirty: ({})
    property bool indexDirty: false

    property bool storeLoaded: false

    // ── Queue and steer (Codex's model) ───────────────────────────────
    // While an answer streams: ↵ steers (the message goes into the running
    // turn: text being written stops, the model answers it), ⇥ queues it for
    // after this answer. Queued messages keep their screenshot and context and
    // send one by one when a turn finishes normally (not after Stop or a
    // failure). Steers the turn couldn't take go back to the front of the queue.
    property var queue: []              // [{ id, text, image, context }]
    property var steering: []           // [{ id, text }] written, not yet taken
    property bool drainAfterTurn: false

    function newId(prefix) { return prefix + Date.now().toString(36) + Math.floor(Math.random() * 1e4).toString(36); }

    function enqueue(text) {
        const t = (text || "").trim();
        if (!t && !pendingImage) return;
        root.queue = root.queue.concat([{ id: newId("q-"), text: t, image: root.pendingImage, context: root.pendingContext, session: root.activeSessionId }]);
        root.pendingImage = ""; root.pendingContext = null; root.pendingAppTitle = "";
    }

    function steer(text) {
        const t = (text || "").trim();
        if (!t) return;
        // A steer is words only; with a screenshot or context attached it waits its turn.
        if (!busyHere || !chatProc.running || chatProc.sawTurnEnd || pendingImage || pendingContext) { enqueue(t); return; }
        const id = newId("s-");
        root.steering = root.steering.concat([{ id: id, text: t }]);
        chatProc.write(JSON.stringify({ type: "turn.steer", id: id, text: t }) + "\n");
    }

    function removeQueued(id) { root.queue = root.queue.filter(q => q.id !== id); }

    // Pull a queued message back into the prompt to change it.
    function takeQueued(id) {
        const q = root.queue.find(x => x.id === id);
        if (!q) return "";
        removeQueued(id);
        if (q.image) root.pendingImage = q.image;
        if (q.context) root.pendingContext = q.context;
        return q.text;
    }

    function sendQueuedNow(id) {
        const q = root.queue.find(x => x.id === id);
        if (!q) return;
        const here = !q.session || q.session === root.activeSessionId;
        if (busyHere && here && !q.image && !q.context) { removeQueued(id); steer(q.text); return; }
        if (streaming) return;
        removeQueued(id);
        if (here) {
            root.pendingImage = q.image || ""; root.pendingContext = q.context || null;
            send(q.text || "Look at this.");
        } else sendIn(q);                   // queued in another chat: it runs there, in the background
    }
    // A queued message for a chat you've left: its message joins that chat
    // and the turn runs there; the view stays where you are.
    function sendIn(q) {
        const meta = root.sessions.find(x => x.id === q.session);
        if (!meta) return;
        const nowMs = Date.now();
        const c = root.hold(q.session);
        const msgs = c.messages.concat([{ role: "user", text: q.text || "Look at this.", image: q.image || "", context: q.context || null,
                                         time: formatTime(nowMs), timestamp: nowMs, model: meta.model || root.model }]);
        root.held = Object.assign({}, root.held, { [q.session]: { messages: msgs, summary: c.summary, summaryUpTo: c.summaryUpTo } });
        root.patchSession(q.session, { count: msgs.length, updatedAt: nowMs });
        root.markDirty(q.session);
        startTurn(q.session);
    }

    Timer {
        id: drainTimer
        interval: 350
        // Next: this chat's queue first, then another chat's.
        onTriggered: {
            if (root.streaming || !root.queue.length) return;
            const q = root.queue.find(x => !x.session || x.session === root.activeSessionId) || root.queue[0];
            root.sendQueuedNow(q.id);
        }
    }

    // Compaction (bin/kuwai_agent.py `compact`): a note standing in for
    // messages[0 .. summaryUpTo), kept with the chat.
    property string summary: ""
    property int summaryUpTo: 0
    readonly property real compactAt: 0.75      // of the context window

    // Tokens the last turn used (prompt + answer) against the window it ran with.
    readonly property int contextUsed: lastStats ? (lastStats.promptEvalCount || 0) + (lastStats.evalCount || 0) : 0
    // The window each model gets. Qwen3.5's hybrid attention keeps its KV cache
    // small: 16k fits beside the desktop in 6 GB at 27 tok/s (8k: 36, measured
    // 2026-11-03). Older 8B models need all of it at 4k.
    // The 8B gets 8k: the system prompt and 20 tools are ~2,500 tokens, 61% of 4k.
    function contextFor(m) { return /qwen3\.5/.test(m || "") ? 16384 : /(8b|20b|30b)/.test(m || "") ? 8192 : 4096; }
    readonly property int contextTotal: lastStats && lastStats.numCtx ? lastStats.numCtx : contextFor(model)

    function modelLabel(m) {
        if (!m) return "";
        let base = m.split(":")[0].replace(/^[\w.-]+\//, "");       // huihui_ai/qwen3-abliterated → qwen3-abliterated
        const uncensored = /-abliterated$/.test(base);
        base = base.replace(/-abliterated$/, "");
        const known = { "hermes3": "Hermes 3", "deepseek-r1": "DeepSeek R1", "minicpm-v": "MiniCPM-V", "qwen3.5": "Qwen 3.5",
                        "qwen3": "Qwen 3", "llama3.2": "Llama 3.2", "llama3.1": "Llama 3.1", "gemma3": "Gemma 3" };
        const tag = m.indexOf(":") >= 0 ? m.split(":")[1] : "";
        const size = /^\d+(\.\d+)?b$/i.test(tag) ? " " + tag.toUpperCase() : "";
        return (known[base] || base) + size + (uncensored ? " Uncensored" : "");
    }

    // The models worth keeping on this rig (6 GB VRAM), from the partner
    // benchmark (docs/research/2026-11-03-partner.md). The picker lists these
    // first with what each is for; anything else installed comes after.
    readonly property var curated: [
        { id: "qwen3.5:4b", role: "Everyday", note: "Fastest and most accurate · sees images · 16k context" },
        { id: "gpt-oss:20b", role: "Deep", note: "Much bigger brain for hard questions · ~17 tok/s, 27 s to load · 8k context" },
        { id: "huihui_ai/qwen3-abliterated:8b", role: "Uncensored", note: "No refusals · accurate, slower · 8k context" }
    ]

    // Retry: drop the answer at `index` (and everything after) and run the
    // turn again from the message before it, with the current model.
    function regenerate(index) {
        if (streaming || index < 1 || index >= messages.length) return;
        if (messages[index].role !== "assistant") return;
        root.messages = Turn.truncateAt(root.messages, index);
        root.dropSummaryPast(index);
        root.syncCurrentSession();
        root.startTurn();
    }

    // Try a failed turn again: rerun from your last message.
    function retry() {
        if (streaming || messages.length === 0) return;
        const last = messages.length - 1;
        if (messages[last].role === "assistant") regenerate(last);
        else startTurn();
    }

    // Edit the message you sent at `index`: later turns go, the edit is resent.
    function editAndResend(index, text) {
        if (streaming || index < 0 || index >= messages.length || messages[index].role !== "user") return;
        const edited = Object.assign({}, messages[index], { text: text, timestamp: Date.now(), time: formatTime(Date.now()) });
        root.messages = [...Turn.truncateAt(root.messages, index), edited];
        root.dropSummaryPast(index);
        root.syncCurrentSession();
        root.startTurn();
    }

    // Cutting the chat back into what the summary covers makes the summary wrong.
    function dropSummaryPast(index) {
        if (index < root.summaryUpTo) { root.summary = ""; root.summaryUpTo = 0; }
    }

    // Parts, plus the flat fields still read elsewhere (text for copy / history /
    // rendering, html, time); the older flat tools / reasoning copies go.
    function withParts(m) {
        if (!m || m.role !== "assistant") return m;
        const msg = Turn.migrateMessage(m);
        const out = Object.assign({}, m, msg, {
            text: Turn.textOf(msg),
            time: m.time || root.formatTime(msg.timestamp)
        });
        delete out.tools;
        delete out.reasoning;
        delete out.tokensPerSec;
        delete out.html;          // rendered on view now (blockHtml), not stored
        delete out.segHtml;
        return out;
    }

    // ── Persistent Sessions Store ─────────────────────────────────────
    // The list (ai-sessions.json) and one file per chat (ai-chats/<id>.json);
    // the rules are ChatStore's (services/ai/chatstore.mjs, tests/shell).
    readonly property string stateDir: Paths.stateHome + "/kuwai"
    readonly property string chatDir: stateDir + "/ai-chats"
    FileView {
        id: sessionStore
        path: root.stateDir + "/ai-sessions.json"
        printErrors: false
        onLoaded: root.openStore(text())
        onLoadFailed: root.openStore("")
    }

    FileView {
        id: sessionBackup
        path: sessionStore.path.replace(/\.json$/, ".bak.json")
        blockWrites: true
        printErrors: false
    }

    // One chat file at a time, read or written now (blocking): a chat is
    // read when it's opened and written before it's let go.
    Component { id: chatReader; FileView { blockAllReads: true; printErrors: false } }
    Component {
        id: chatWriter
        FileView { property int ok: 0; blockWrites: true; atomicWrites: true; printErrors: false; onSaved: ok = 1; onSaveFailed: ok = -1 }
    }
    function readFile(path) {
        if (!path) return "";
        const r = chatReader.createObject(root, { path: path });
        const t = r.text();
        r.destroy();
        return t || "";
    }
    function writeFile(path, text) {
        if (!path) return false;
        const w = chatWriter.createObject(root, { path: path });
        w.setText(text);
        const ok = w.ok === 1;
        w.destroy();
        return ok;
    }
    Component { id: remover; Process { onExited: destroy() } }
    function removeChatFile(id) {
        const p = ChatStore.chatPath(root.chatDir, id);
        if (!p) return;
        const r = remover.createObject(root, { command: ["rm", "-f", "--", p] });
        r.running = true;
    }

    // A chat's content: the open one's, a held one's, else read from its file.
    function loadChat(id) {
        const d = ChatStore.parseChat(root.readFile(ChatStore.chatPath(root.chatDir, id)))
            || (root.legacyDocs ? root.legacyDocs[id] : null);
        if (!d) return { messages: [], summary: "", summaryUpTo: 0 };
        return { messages: d.messages.map(root.withParts), summary: d.summary || "", summaryUpTo: d.summaryUpTo || 0 };
    }
    function contentOf(id) {
        if (id === root.activeSessionId) return { messages: root.messages, summary: root.summary, summaryUpTo: root.summaryUpTo };
        return root.held[id] || root.loadChat(id);
    }
    // Keep a chat other than the open one in memory while a turn uses it.
    function hold(id) {
        if (id === root.activeSessionId) return root.contentOf(id);
        if (!root.held[id]) root.held = Object.assign({}, root.held, { [id]: root.loadChat(id) });
        return root.held[id];
    }
    // Let a held chat go, once its file has what's in memory. Not while its
    // turn runs; a chat whose write failed stays held and is retried by flush.
    function release(id) {
        if (!root.held[id] || id === root.activeSessionId) return;
        if (root.streaming && root.draftSessionId === id) return;
        if (root.dirty[id] && !root.writeChat(id)) return;
        const h = Object.assign({}, root.held); delete h[id]; root.held = h;
    }
    // Leaving the open chat: its file catches up. A turn still answering there,
    // or a write that failed, keeps it held (in memory) instead of dropped.
    function leave(id) {
        if (!id) return;
        const saved = !root.dirty[id] || root.writeChat(id);
        if (!saved || (root.streaming && root.draftSessionId === id && !root.discardDraft))
            root.held = Object.assign({}, root.held, { [id]: { messages: root.messages, summary: root.summary, summaryUpTo: root.summaryUpTo } });
    }
    function markDirty(id) {
        if (id) root.dirty = Object.assign({}, root.dirty, { [id]: true });
        root.indexDirty = true;
        saveDelay.restart();
    }
    // Write one chat's file from memory (nothing to write if it isn't there).
    function writeChat(id) {
        if (!root.storeLoaded) return false;
        const meta = root.sessions.find(s => s.id === id);
        const inMem = id === root.activeSessionId || !!root.held[id];
        if (!meta || !inMem) { const d = Object.assign({}, root.dirty); delete d[id]; root.dirty = d; return true; }
        const c = root.contentOf(id);
        const ok = root.writeFile(ChatStore.chatPath(root.chatDir, id), ChatStore.chatText(ChatStore.chatDoc(meta, c.messages, c.summary, c.summaryUpTo)));
        if (ok) { const d = Object.assign({}, root.dirty); delete d[id]; root.dirty = d; }
        else console.warn("OllamaService: couldn't save chat " + id + " (kept in memory, retried on the next save)");
        return ok;
    }
    // Chats first, then the list, so the list never names a file that isn't written.
    function flush() {
        if (!root.storeLoaded) return;
        for (const id of Object.keys(root.dirty)) root.writeChat(id);
        // Held chats no turn needs any more leave memory once written.
        for (const id of Object.keys(root.held)) if (!root.dirty[id]) root.release(id);
        if (root.indexDirty) {
            sessionStore.setText(ChatStore.indexText(root.sessions));
            root.indexDirty = false;
        }
    }
    Timer {
        id: saveDelay
        interval: 400
        onTriggered: root.flush()
    }

    // Start: read the list; an old one (whole chats in one file) is split
    // into chat files once, and chat files the list lost are put back.
    property var legacyDocs: null         // only if the split couldn't write: chats read from the old file
    function openStore(text) {
        const idx = ChatStore.readIndex(text);
        if (idx.kind === "newer") {
            // A later kuwai's list: read it as nothing and never write over it.
            console.warn("OllamaService: ai-sessions.json is from a newer version; chats are not saved this session");
            root.ensureInitialSession();
            return;
        }
        if (idx.kind === "bad") {
            // Not a list: keep it aside; the chat files rebuild the list (orphans below).
            root.writeFile(root.stateDir + "/ai-sessions.bad.json", text);
        }
        if (idx.kind === "v2" || idx.kind === "legacy") sessionBackup.setText(text);   // a bad save can't take the list with it
        let wrote = true;
        if (idx.kind === "legacy") wrote = root.splitLegacy(text, idx.docs);
        root.sessions = idx.chats;
        if (idx.chats.length > 0) {
            const first = idx.chats[0];
            const c = root.loadChat(first.id);
            root.activeSessionId = first.id;
            root.messages = c.messages;
            root.summary = c.summary;
            root.summaryUpTo = c.summaryUpTo;
            if (first.model) root.model = first.model;
            root.mode = first.mode || "chat";
        }
        root.ensureInitialSession();
        if (!wrote) return;                // storeLoaded stays false: nothing overwrites the old file
        root.storeLoaded = true;
        if (idx.kind === "legacy" || idx.kind === "bad") { root.indexDirty = true; root.flush(); }
        orphanScan.running = true;
    }
    // The one-time split. Returns false (and writes no list) if a chat file couldn't be written.
    function splitLegacy(text, docs) {
        const keep = root.stateDir + "/ai-sessions.legacy.json";
        if (!root.readFile(keep) && !root.writeFile(keep, text)) {
            console.warn("OllamaService: couldn't copy ai-sessions.json aside; chats stay in the old file this session");
            root.legacyDocs = root.docsById(docs);
            return false;
        }
        for (const d of docs) {
            const p = ChatStore.chatPath(root.chatDir, d.id);
            if (!ChatStore.shouldWriteLegacy(root.readFile(p), d)) continue;
            if (!root.writeFile(p, ChatStore.chatText(d))) {
                console.warn("OllamaService: couldn't write " + p + "; chats stay in the old file this session");
                root.legacyDocs = root.docsById(docs);
                return false;
            }
        }
        return true;
    }
    function docsById(docs) { const m = {}; for (const d of docs) m[d.id] = d; return m; }
    Process {
        id: orphanScan
        command: ["find", root.chatDir, "-maxdepth", "1", "-type", "f", "-name", "*.json", "-printf", "%f\\n"]
        stdout: StdioCollector { onStreamFinished: root.adoptOrphans(text) }
    }
    // `names`: the chat folder's file names, one a line.
    function adoptOrphans(names) {
        const listed = {};
        for (const s of root.sessions) listed[s.id] = true;
        const docs = [];
        for (const name of names.split("\n")) {
            const id = name.replace(/\.json$/, "");
            if (!ChatStore.validId(id) || listed[id]) continue;
            const d = ChatStore.parseChat(root.readFile(ChatStore.chatPath(root.chatDir, id)));
            if (d) docs.push(d);
        }
        const back = ChatStore.orphansToMetas(root.sessions, docs);
        if (!back.length) return;
        root.sessions = root.sessions.concat(back);
        root.indexDirty = true;
        saveDelay.restart();
    }

    function formatTime(timestamp) {
        if (!timestamp) return "";
        return Dates.time(timestamp);
    }

    function ensureInitialSession() {
        if (root.sessions.length === 0) {
            const initId = Date.now().toString();
            root.sessions = [ChatStore.metaOf({ id: initId, title: "New Chat", model: root.model, mode: root.mode, updatedAt: Date.now() }, 0)];
            root.activeSessionId = initId;
            root.messages = [];
            root.indexDirty = true;
        }
    }

    function newChat() {
        syncCurrentSession();
        const newId = Date.now().toString();
        const newSess = ChatStore.metaOf({ id: newId, title: "New Chat", model: root.model, mode: root.mode, updatedAt: Date.now() }, 0);
        // Reuse the current chat only if it's the empty one; never overwrite another
        // (this used to replace sessions[0], which could be a real chat).
        const cur = root.sessions.findIndex(x => x.id === root.activeSessionId);
        if (cur >= 0 && root.messages.length === 0 && !(root.streaming && root.draftSessionId === root.activeSessionId)) {
            const gone = root.activeSessionId;
            const updated = [...root.sessions];
            updated[cur] = newSess;
            root.sessions = updated;
            const d = Object.assign({}, root.dirty); delete d[gone]; root.dirty = d;
            root.removeChatFile(gone);
        } else {
            root.leave(root.activeSessionId);
            root.sessions = [newSess, ...root.sessions];
        }
        root.activeSessionId = newId;
        root.messages = [];
        root.summary = "";
        root.summaryUpTo = 0;
        root.lastStats = null;
        root.pendingImage = "";
        root.pendingContext = null;
        root.pendingAppTitle = "";
        root.errorText = "";
        root.indexDirty = true;
        saveDelay.restart();
    }

    // ── Application Launching & Tool Execution ─────────────────────────
    function findApp(query) {
        if (!query) return null;
        const q = query.toLowerCase().trim();
        if (!q) return null;
        if (typeof DesktopEntries === "undefined" || !DesktopEntries.applications) return null;
        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay);
        // 1. Exact match on name or id
        for (let i = 0; i < apps.length; i++) {
            if (apps[i].name && apps[i].name.toLowerCase() === q) return apps[i];
            if (apps[i].id && apps[i].id.toLowerCase() === q) return apps[i];
        }
        // 2. Starts with match
        for (let i = 0; i < apps.length; i++) {
            if (apps[i].name && apps[i].name.toLowerCase().startsWith(q)) return apps[i];
        }
        // 3. Substring match
        for (let i = 0; i < apps.length; i++) {
            if (apps[i].name && apps[i].name.toLowerCase().indexOf(q) >= 0) return apps[i];
            if (apps[i].comment && apps[i].comment.toLowerCase().indexOf(q) >= 0) return apps[i];
        }
        return null;
    }

    function launchApp(appQuery) {
        const found = findApp(appQuery);
        const nowMs = Date.now();
        const timeStr = formatTime(nowMs);
        const nameToLaunch = found ? found.name : appQuery;

        // Only real apps (desktop entries) open; a typed string is never run as a program (red-team 9).
        if (!found) {
            root.errorText = "No app called " + appQuery;
            return;
        }
        Apps.launch(found);

        const userMsg = {
            role: "user",
            text: "Launch " + nameToLaunch,
            html: "",
            reasoning: "",
            tools: [],
            image: "",
            time: timeStr,
            timestamp: nowMs,
            model: root.model,
            tokensPerSec: 0
        };

        const assistMsg = {
            role: "assistant",
            text: "Launched **" + nameToLaunch + "**.",
            html: "<p>Launched <strong>" + nameToLaunch + "</strong>.</p>",
            reasoning: "",
            tools: [{
                name: "launch_app",
                title: "Launch Application",
                state: "completed",
                input: { app: nameToLaunch },
                output: "Successfully dispatched " + nameToLaunch + " on active workspace",
                errorText: ""
            }],
            image: "",
            time: timeStr,
            timestamp: nowMs + 10,
            model: root.model,
            tokensPerSec: 0
        };

        root.messages = [...root.messages, userMsg, root.withParts(assistMsg)];
        root.syncCurrentSession();
        return true;
    }

    function recordToolLaunch(appName) {
        return launchApp(appName);
    }

    // Fork (AI Elements branch / checkpoint): a new chat with this one's messages up
    // to `index` (all of them if index < 0), optionally on another model. The
    // original stays as it was. The summary comes along when it covers only those.
    function forkAt(index, model) {
        if (streaming) return;
        syncCurrentSession();
        const src = root.sessions.find(s => s.id === root.activeSessionId);
        const msgs = (index === undefined || index < 0 ? root.messages : root.messages.slice(0, index + 1))
            .map(m => Object.assign({}, m));
        if (msgs.length === 0) { if (model) root.model = model; return; }
        const keep = root.summaryUpTo > 0 && root.summaryUpTo <= msgs.length;
        const now = Date.now();
        const sess = ChatStore.metaOf({
            id: now.toString(),
            title: ((src && src.title && src.title !== "New Chat") ? src.title : "Chat").replace(/ \(fork\)$/, "") + " (fork)",
            renamed: true, model: model || root.model, mode: root.mode, updatedAt: now
        }, msgs.length);
        root.leave(root.activeSessionId);
        root.sessions = [sess, ...root.sessions];
        root.activeSessionId = sess.id;
        root.messages = msgs;
        root.summary = keep ? root.summary : "";
        root.summaryUpTo = keep ? root.summaryUpTo : 0;
        root.model = sess.model;
        root.errorText = "";
        root.markDirty(sess.id);
    }

    function switchSession(id) {
        if (id === root.activeSessionId) return;

        const found = root.sessions.find(s => s.id === id);
        if (found) {
            syncCurrentSession();
            root.leave(root.activeSessionId);
            // Held (a turn is answering there): take it as it is in memory; else read its file.
            const c = root.held[id] || root.loadChat(id);
            if (root.held[id]) { const h = Object.assign({}, root.held); delete h[id]; root.held = h; }
            if (root.unread[id]) { const u = Object.assign({}, root.unread); delete u[id]; root.unread = u; }
            root.activeSessionId = id;
            root.messages = c.messages;
            root.summary = c.summary;
            root.summaryUpTo = c.summaryUpTo;
            root.lastStats = null;
            if (found.model) root.model = found.model;
            root.mode = found.mode || "chat";
            root.pendingImage = "";
            root.errorText = "";
        }
    }

    function renameSession(id, title) {
        const t = String(title || "").trim().split("\n")[0].slice(0, 80);
        const i = root.sessions.findIndex(s => s.id === id);
        if (i < 0 || !t) return;
        const updated = [...root.sessions];
        updated[i] = Object.assign({}, updated[i], { title: t, renamed: true });
        root.sessions = updated;
        root.indexDirty = true;
        saveDelay.restart();
    }

    function deleteSession(id) {
        if (streaming && root.draftSessionId === id) abandon();

        const filtered = root.sessions.filter(s => s.id !== id);
        root.sessions = filtered;
        if (root.held[id]) { const h = Object.assign({}, root.held); delete h[id]; root.held = h; }
        if (root.dirty[id]) { const d = Object.assign({}, root.dirty); delete d[id]; root.dirty = d; }
        root.removeChatFile(id);

        if (root.activeSessionId === id) {
            if (filtered.length > 0) {
                const c = root.held[filtered[0].id] || root.loadChat(filtered[0].id);
                if (root.held[filtered[0].id]) { const h = Object.assign({}, root.held); delete h[filtered[0].id]; root.held = h; }
                root.activeSessionId = filtered[0].id;
                root.messages = c.messages;
                root.summary = c.summary;
                root.summaryUpTo = c.summaryUpTo;
                if (filtered[0].model) root.model = filtered[0].model;
            } else {
                ensureInitialSession();
            }
        }
        root.indexDirty = true;
        saveDelay.restart();
    }

    // List fields only (title, count, updatedAt…); messages go through markDirty.
    function patchSession(id, fields) {
        const i = root.sessions.findIndex(x => x.id === id);
        if (i < 0) return;
        const updated = [...root.sessions];
        updated[i] = Object.assign({}, updated[i], fields);
        root.sessions = updated;
        root.indexDirty = true;
        saveDelay.restart();
    }

    // The open chat's list entry follows what's in memory; its file is written on the next save.
    function syncCurrentSession() {
        const idx = root.sessions.findIndex(s => s.id === root.activeSessionId);
        if (idx >= 0) {
            const curr = Object.assign({}, root.sessions[idx]);
            curr.count = root.messages.length;
            curr.model = root.model;
            curr.mode = root.mode;
            curr.updatedAt = Date.now();
            const updated = [...root.sessions];
            updated[idx] = curr;
            root.sessions = updated;
            root.markDirty(root.activeSessionId);
        }
    }

    property string clearPendingSession: ""
    function requestClear() { root.clearPendingSession = root.activeSessionId; }
    function cancelClear() { root.clearPendingSession = ""; }
    function confirmClear() {
        const id = root.clearPendingSession;
        root.clearPendingSession = "";
        if (id && id === root.activeSessionId) clear();
    }

    function clear() {
        if (streaming && root.draftSessionId === root.activeSessionId) abandon();
        root.queue = root.queue.filter(q => q.session !== root.activeSessionId);
        root.messages = [];
        root.summary = "";
        root.summaryUpTo = 0;
        root.pendingImage = "";
        root.pendingContext = null;
        root.pendingAppTitle = "";
        root.errorText = "";
        syncCurrentSession();
    }

    // Stop: the agent declines any pending approval, ends the turn as
    // "interrupted", and the partial answer is kept (finishTurn on exit).
    function cancel() {
        if (chatProc.running) chatProc.signal(15);
        else streaming = false;
    }

    // Stop and throw the partial answer away (leaving this chat).
    function abandon() {
        // Invalidate only work that exists now. New prompts may queue while exit is delayed.
        root.queue = root.queue.filter(q => q.session !== root.draftSessionId);
        root.steering = [];
        root.pendingDeltas = [];
        deltaTimer.stop();
        discardDraft = true;
        cancel();
    }

    // An approval (accept / decline) or a question's answer (accept + answer text).
    function resolveRequest(id, decision, answer) {
        if (!chatProc.running || root.discardDraft || !root.pendingRequest || root.pendingRequest.id !== id) return;
        const msg = { type: "request.resolve", id: id, decision: decision };
        if (answer) msg.answer = answer;
        chatProc.write(JSON.stringify(msg) + "\n");
    }

    // ── Status Probing ────────────────────────────────────────────────
    function probe() {
        if (!probeProc.running) {
            probeProc.running = true;
        }
    }

    Timer {
        id: probeTimer
        // Only the assistant's own window shows the status and the models
        // (AssistantOverlay, its model picker): probed while it's open or an
        // answer streams, never while closed (it was once a minute, a Python
        // start for nobody). Once at start, so the window opens on the last
        // known status rather than "offline" for a moment.
        interval: 12000
        running: Assistant.open || root.streaming
        repeat: true
        onTriggered: root.probe()
    }
    Component.onCompleted: root.probe()
    // Opened: fresh status at once.
    Connections { target: Assistant; function onOpenChanged() { if (Assistant.open) root.probe(); } }

    Process {
        id: probeProc
        command: [root.bin, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                if (!out) return;
                try {
                    const data = JSON.parse(out);
                    root.status = data.status || "offline";
                    if (Array.isArray(data.models) && data.models.length > 0) {
                        root.availableModels = data.models;
                        if (root.availableModels.indexOf(root.model) === -1 && root.availableModels.length > 0) {
                            root.model = root.availableModels[0];
                        }
                    }
                    root.runningModels = data.running || [];
                    if (data.info) root.modelInfo = data.info;
                } catch (e) {
                    root.status = "offline";
                }
            }
        }
    }

    // ── Unload VRAM when closed ───────────────────────────────────────
    // ── Clipboard Image Pasting ───────────────────────────────────────
    function pasteClipboardImage() {
        pasteProc.running = false;
        pasteProc.running = true;
    }

    Process {
        id: pasteProc
        command: [root.bin, "paste"]
        property string capturedPath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                pasteProc.capturedPath = text.trim();
            }
        }
        onExited: exitCode => {
            // No model switch: a model that can't see gets a description (the agent's vision hop).
            if (exitCode === 0 && pasteProc.capturedPath !== "") {
                root.pendingImage = pasteProc.capturedPath;
            }
            pasteProc.capturedPath = "";
        }
    }

function onPanelClosed() {
        // The model stays loaded for Ollama's keep_alive (5 min) so reopening is instant;
        // it was unloaded on every close, which made each reopen wait ~5 s.
    }

    // ── Background work and notifications ─────────────────────────────
    // A turn keeps running with the overlay closed; when it ends (or needs you),
    // a notification says so and its Open button brings the assistant back.
    readonly property string kuwaiBin: Paths.bin + "/kuwai"
    readonly property string notifyBin: Paths.bin + "/kuwai-notify"
    function notify(title, body, urgency) {
        const p = notifyComponent.createObject(root, { command: ["sh", "-c",
            'r=$("$6" -a Assistant -i chat-bubbles -u "$3" -w -A open=Open -- "$1" "$2"); [ "$r" = open ] && "$5" assistant open',
            "sh", title, body, urgency || "normal", root.kuwaiBin, root.notifyBin] });
        p.running = true;
    }
    Component {
        id: notifyComponent
        Process { onExited: destroy(100) }
    }
    function notifyPending() {
        const r = root.pendingRequest;
        if (!r || Assistant.open) return;
        const part = root.draft ? root.draft.parts.find(q => q.id === r.partId) : null;
        const req = part ? part.request : {};
        root.notify(r.kind === "question" ? "The assistant has a question" : "The assistant is waiting for you",
                    (req.summary || "") + (req.detail ? "\n" + req.detail.slice(0, 160) : ""), "critical");
    }
    // Background jobs (sandbox_run background=true): while any run, look every 10 s
    // for finished ones and say so.
    property var runningJobs: []
    Timer {
        interval: 10000
        repeat: true
        running: root.runningJobs.length > 0
        onTriggered: if (!jobsProc.running) jobsProc.running = true
    }
    Process {
        id: jobsProc
        command: [root.bin, "sandbox", "jobs"]
        stdout: StdioCollector {
            onStreamFinished: {
                let done = [];
                try { done = JSON.parse(text.trim() || "[]"); } catch (e) { return; }
                done.forEach(j => {
                    root.notify(j.exit === "0" ? "Job finished" : "Job failed (exit " + j.exit + ")", j.command);
                    root.runningJobs = root.runningJobs.filter(x => x !== j.id);
                });
            }
        }
    }

    // What it's doing, for the island's stacked row.
    property real workStarted: 0
    onStreamingChanged: if (streaming) workStarted = Date.now()
    function workLabel() {
        const d = root.draft;
        if (root.pendingRequest) return "Needs you";
        const p = d && d.parts.length ? d.parts[d.parts.length - 1] : null;
        if (!p || p.kind === "reasoning") return "Thinking";
        if (p.kind === "text") return "Writing";
        const t = (p.title || "").replace(/^⏵ /, "");
        return t.length > 26 ? t.slice(0, 25) + "…" : t;
    }
    // The island stacks this under its rest row (IslandBar: assistRow) while the
    // assistant works with the panel closed, and lists recent background work
    // when it's expanded (IslandHover).
    readonly property bool bgWorking: streaming && !Assistant.open
    property string bgLabel: ""
    property int bgSecs: 0
    property var bgDone: null              // { status, title } for a few seconds after
    property var recentWork: []            // [{ sessionId, title, status, at }], newest first
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.bgWorking
        onTriggered: { root.bgLabel = root.workLabel(); root.bgSecs = Math.round((Date.now() - root.workStarted) / 1000); }
    }
    Timer { id: bgDoneClear; interval: 5000; onTriggered: root.bgDone = null }
    function openSession(id) {
        if (id) root.switchSession(id);
        Assistant.show();
    }

    function notifyDone(msg) {
        if (!Assistant.open && msg) {
            const sess = root.sessions.find(s => s.id === root.draftSessionId);
            const title = sess && sess.title && sess.title !== "New Chat" ? sess.title : "Your chat";
            const ok = msg.status !== "failed";
            root.bgDone = { status: ok ? "done" : "failed", title: title, sessionId: root.draftSessionId };
            bgDoneClear.restart();
            root.recentWork = [{ sessionId: root.draftSessionId, title: title, status: ok ? "done" : "failed", at: Date.now() }]
                .concat(root.recentWork.filter(w => w.sessionId !== root.draftSessionId)).slice(0, 3);
        }
        if (Assistant.open || !msg) return;
        const sess = root.sessions.find(s => s.id === root.draftSessionId);
        const text = Turn.textOf(msg).replace(/\s+/g, " ").trim();
        root.notify(msg.status === "failed" ? "The assistant hit a problem" : "Done: " + (sess ? sess.title : "your chat"),
                    msg.status === "failed" ? (msg.error || "The turn failed") : (text.slice(0, 180) || "Finished."));
    }

    Process {
        id: unloadProc
        command: [root.bin, "unload"]
    }

        // ── T3 Code-Style Window Snapshotting ─────────────────────────────
    function snapshotActiveWindow() {
        Assistant.sniping = true;
        Assistant.hide();
        snapWinTimer.restart();
    }

    Timer {
        id: snapWinTimer
        interval: 100
        onTriggered: {
            snapWinProc.running = false;
            snapWinProc.running = true;
        }
    }

    Process {
        id: snapWinProc
        command: [root.bin, "snapshot", "window"]
        property string rawOutput: ""
        stdout: StdioCollector {
            onStreamFinished: {
                snapWinProc.rawOutput = text.trim();
            }
        }
        onExited: exitCode => {
            Assistant.sniping = false;
            if (exitCode === 0 && snapWinProc.rawOutput !== "") {
                try {
                    const data = JSON.parse(snapWinProc.rawOutput);
                    if (data.status === "ok" && data.path) {
                        root.pendingImage = data.path;
                        root.pendingContext = {
                            app: data.app || "", title: data.title || "", workspace: data.workspace || "",
                            cwd: data.cwd || "", git: data.git || null, terminal: data.terminal || null,
                            selection: data.selection || "", clipboard: data.clipboard || ""
                        };
                        root.pendingAppTitle = (data.app || "App") + (data.title ? ": " + data.title : "");
                    }
                } catch (e) {}
            }
            snapWinProc.rawOutput = "";
            Assistant.show();
        }
    }

    // The chat's sandbox folder. Same root and slug as bin/kuwai_sandbox.py
    // (host_root, chat_slug): KUWAI_SANDBOX_DIR overrides the root, and leading
    // dots are stripped so an id cannot land on ".", ".." or ".home".
    function sandboxDir(chatId) {
        // The jail (bin/kuwai_sandbox.py host_root): ~/Depot/kuwai-sandbox, where you can watch it.
        const base = (Quickshell.env("KUWAI_SANDBOX_DIR") || (Quickshell.env("HOME") + "/Depot/kuwai-sandbox")).replace(/\/+$/, "");
        const slug = String(chatId || root.activeSessionId || "").replace(/[^A-Za-z0-9_.-]/g, "").replace(/^\.+/, "").slice(0, 64) || "scratch";
        return base + "/" + slug;
    }

// ── Attachments: files (text, code, PDF) and images ───────────────
    // Text and PDFs go to the agent as their text (and into the sandbox, so
    // code can work on them); an image becomes the message's picture.
    readonly property var imageExt: /\.(png|jpe?g|webp|gif|bmp)$/i
    function attach(path) {
        const p = String(path || "").trim().replace(/^file:\/\//, "");
        if (!p) return;
        if (imageExt.test(p) && !root.pendingImage) { root.pendingImage = p; return; }
        const c = Object.assign({}, root.pendingContext || {});
        const files = (c.files || []).filter(f => f.path !== p);
        files.push({ path: p, name: p.split("/").pop() });
        c.files = files.slice(-6);
        root.pendingContext = c;
    }
    function pickFiles() {
        if (!filePicker.running) filePicker.running = true;
    }
    Process {
        id: filePicker
        command: ["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Attach files",
                  "--filename=" + Quickshell.env("HOME") + "/"]
        stdout: StdioCollector {
            onStreamFinished: text.split("\n").forEach(p => root.attach(p))
        }
    }

// ── Screenshot Workflow (no grab conflict) ────────────────────────
    function takeScreenshot() {
        Assistant.sniping = true;
        Assistant.hide();
        snipTimer.restart();
    }

    Timer {
        id: snipTimer
        interval: 120
        onTriggered: {
            snipProc.running = false;
            snipProc.running = true;
        }
    }

    Process {
        id: snipProc
        command: [root.bin, "snip"]
        property string capturedPath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                snipProc.capturedPath = text.trim();
            }
        }
        onExited: exitCode => {
            Assistant.sniping = false;
            if (exitCode === 0 && snipProc.capturedPath !== "") {
                root.pendingImage = snipProc.capturedPath;
            }
            snipProc.capturedPath = "";
            Assistant.show();
        }
    }

    // ── Send Chat Turn ────────────────────────────────────────────────
    FileView {
        id: reqFileWriter
        path: root.reqPath
        printErrors: false
    }

    function send(promptText) {
        if (!promptText || promptText.trim() === "") return;
        // Another chat is answering: this one waits its turn (it shows as queued).
        if (streaming && !busyHere) { enqueue(promptText); return; }
        if (streaming) return;

        const trimmedPrompt = promptText.trim();
        // Check for slash commands or direct app launches
        if (trimmedPrompt.startsWith("/open ") || trimmedPrompt.startsWith("/launch ")) {
            const appQuery = trimmedPrompt.replace(/^\/(open|launch)\s+/, "").trim();
            launchApp(appQuery);
            return;
        } else if (trimmedPrompt === "/clear") {
            requestClear();
            return;
        } else if (trimmedPrompt === "/new") {
            newChat();
            return;
        } else if (trimmedPrompt === "/snap") {
            snapshotActiveWindow();
            return;
        }

        // Natural language app launch detection: e.g. "open kitty", "launch code", "open spotify"
        const launchMatch = trimmedPrompt.match(/^(?:open|launch)\s+([a-zA-Z0-9_\-\s]+)$/i);
        if (launchMatch) {
            const targetApp = launchMatch[1].trim();
            const app = findApp(targetApp);
            if (app) {
                launchApp(app.name);
                return;
            }
        }

        errorText = "";
        const nowMs = Date.now();
        const timeStr = formatTime(nowMs);
        const userImg = root.pendingImage;

        // Auto-title session from first prompt if "New Chat"
        const idx = root.sessions.findIndex(s => s.id === root.activeSessionId);
        if (idx >= 0 && !root.sessions[idx].renamed && (root.sessions[idx].title === "New Chat" || root.messages.length === 0)) {
            const trimmed = promptText.trim();
            // The first line, up to 80 characters; the views elide it to fit.
            const line = trimmed.split("\n")[0];
            const autoTitle = line.length > 80 ? line.slice(0, 80) + "…" : line;
            const curr = Object.assign({}, root.sessions[idx]);
            curr.title = autoTitle;
            curr.updatedAt = nowMs;
            const updated = [...root.sessions];
            updated[idx] = curr;
            root.sessions = updated;
        }

        const userMsg = {
            role: "user",
            text: promptText,
            image: userImg,
            context: root.pendingContext,
            time: timeStr,
            timestamp: nowMs,
            model: root.model
        };
        root.pendingContext = null;
        root.pendingAppTitle = "";
        root.pendingImage = "";
        root.messages = [...root.messages, userMsg];
        root.syncCurrentSession();
        root.startTurn();
    }

    // Runs the agent on the current history (the last message is the user's).
    function startTurn(sessionId) {
        const sid = sessionId || root.activeSessionId;
        const here = sid === root.activeSessionId;
        const bg = here ? null : root.sessions.find(x => x.id === sid);
        if (!here && !bg) return;
        const held = here ? null : root.hold(sid);          // in memory until its turn ends
        const msgs = here ? root.messages : held.messages;
        const summary = here ? root.summary : (held.summary || "");
        const upTo = here ? root.summaryUpTo : (held.summaryUpTo || 0);
        const model = here ? root.model : (bg.model || root.model);
        const mode = here ? root.mode : (bg.mode || "chat");
        if (here) errorText = "";
        root.discardDraft = false;
        root.draftSessionId = sid;
        root.draft = Turn.newAssistant(model, Date.now());
        root.streaming = true;

        const sent = Turn.toApiMessagesWithIndex(msgs.slice(upTo), upTo);
        // Compact when the last turn filled 3/4 of the window, or the history
        // looks that big (≈4 characters a token, plus ~900 for the system prompt and tools).
        const chars = sent.api.reduce((n, m) => n + (m.content || "").length, summary.length);
        const estimate = chars / 4 + 2600;     // + system prompt, context and 20 tool schemas (measured 2,499)
        const ctx = root.contextFor(model);
        const compact = root.compactNext || Math.max(here ? root.contextUsed : 0, estimate) >= root.compactAt * ctx;
        root.compactNext = false;
        chatProc.sentIndex = sent.index;
        chatProc.sentUpTo = upTo;

        reqFileWriter.setText(JSON.stringify({
            model: model,
            messages: sent.api,
            summary: summary,
            compact: compact,
            chat: sid,
            mode: mode,
            keep_alive: "5m",
            options: { num_ctx: ctx, temperature: model.indexOf("hermes") >= 0 ? 0.4 : 0.7 }
        }, null, 2));

        chatProc.sawTurnEnd = false;
        chatProc.running = false;
        chatProc.running = true;
    }

    Process {
        id: chatProc
        property bool sawTurnEnd: false
        property var sentIndex: []
        property int sentUpTo: 0
        command: [root.bin, "agent", root.reqPath]
        stdinEnabled: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (!line || line.trim() === "") return;
                let ev;
                try { ev = JSON.parse(line); } catch (e) { return; }
                // Cleared/deleted turns cannot restore compaction, steers or deltas on exit.
                if (root.discardDraft) { if (ev.type === "turn.completed") chatProc.sawTurnEnd = true; return; }
                // Text arrives a token at a time; fold the tokens into one update a frame
                // (T3 Code merges per 50 ms on its server). Anything else lands at once, in order.
                if (ev.type === "item.delta") {
                    root.pendingDeltas.push(ev);
                    if (!deltaTimer.running) deltaTimer.start();
                    return;
                }
                root.flushDeltas();
                root.draft = Turn.applyEvent(root.draft, ev);
                if (ev.type === "request.opened") Qt.callLater(root.notifyPending);
                if (ev.type === "item.completed" && /^Started background job (j[0-9a-f]+)/.test(ev.output || ""))
                    root.runningJobs = root.runningJobs.concat([/^Started background job (j[0-9a-f]+)/.exec(ev.output)[1]]);
                if (ev.type === "item.completed" && ev.status === "completed" && root.draft) {
                    const p = root.draft.parts.find(q => q.id === ev.id);
                    if (p && p.itemType === "context_compaction") {
                        const upTo = Turn.compactedUpTo(chatProc.sentUpTo, chatProc.sentIndex, (p.input || {}).kept || 0);
                        if (root.draftSessionId === root.activeSessionId) {
                            root.summary = ev.output || "";
                            root.summaryUpTo = upTo;
                            root.syncCurrentSession();
                        } else {
                            // The chat it's answering in is held while the turn runs.
                            const sid = root.draftSessionId;
                            const c = root.hold(sid);
                            root.held = Object.assign({}, root.held, { [sid]: { messages: c.messages, summary: ev.output || "", summaryUpTo: upTo } });
                            root.markDirty(sid);
                        }
                    }
                }
                if (ev.type === "turn.steered") root.steering = root.steering.filter(x => x.id !== ev.id);
                if (ev.type === "turn.completed") {
                    // Steers it couldn't take (and any still in flight) wait at the front of the queue.
                    const back = (ev.unapplied || []).concat(root.steering)
                        .filter((x, i, a) => a.findIndex(y => y.id === x.id) === i)
                        .map(x => ({ id: x.id, text: x.text, image: "", context: null, session: root.draftSessionId }));
                    if (back.length) root.queue = back.concat(root.queue);
                    root.steering = [];
                    root.drainAfterTurn = ev.status === "completed" || ev.status === "max_tool_rounds" || ev.status === "repeating";
                    chatProc.sawTurnEnd = true;
                    if (root.busyHere) root.lastStats = ev.stats || null;
                    if (ev.status === "failed" && root.busyHere) root.errorText = ev.error || "The turn failed.";
                }
            }
        }
        onExited: exitCode => {
            if (!chatProc.sawTurnEnd && !root.discardDraft && root.errorText === "" && root.busyHere) {
                root.errorText = "The assistant stopped unexpectedly (exit " + exitCode + ").";
            }
            root.finishTurn();
        }
    }

    // "/ Summarise this chat now": the next turn compacts first, whatever the meter says.
    property bool compactNext: false

    property var pendingDeltas: []
    function flushDeltas() {
        deltaTimer.stop();
        if (!pendingDeltas.length) return;
        const evs = pendingDeltas;
        pendingDeltas = [];
        // Consecutive deltas to one item become one.
        const merged = [];
        evs.forEach(e => {
            const last = merged[merged.length - 1];
            if (last && last.id === e.id) last.text += e.text || "";
            else merged.push({ type: "item.delta", id: e.id, text: e.text || "", ts: e.ts });
        });
        let d = root.draft;
        merged.forEach(e => { d = Turn.applyEvent(d, e); });
        root.draft = d;
    }
    // 50 ms, as T3 Code lands text: whole words and phrases arrive together instead
    // of a ragged token at a time, and the live block re-renders 20 times a second.
    Timer { id: deltaTimer; interval: 50; onTriggered: root.flushDeltas() }

    // The draft becomes a message in the chat it was started in.
    function finishTurn() {
        root.flushDeltas();
        const d = root.draft;
        const keep = d && !root.discardDraft && d.parts.length > 0;
        if (keep && d.status !== "interrupted") root.notifyDone(d);
        root.streaming = false;
        root.draft = null;
        const discarded = root.discardDraft;
        if (discarded) root.steering = [];
        root.discardDraft = false;
        // Queued in another chat: it runs next whatever this turn's end was.
        if ((discarded || root.drainAfterTurn || root.queue.some(q => q.session && q.session !== root.draftSessionId)) && root.queue.length > 0) drainTimer.restart();
        root.drainAfterTurn = false;
        const sid = root.draftSessionId;
        if (!keep) { root.release(sid); return; }

        const msg = root.withParts(Object.assign({}, d, { time: formatTime(Date.now()) }));
        if (sid === root.activeSessionId) {
            const updated = [...root.messages, msg];
            root.messages = updated;
            root.syncCurrentSession();
        } else {
            // You moved to another chat meanwhile: the answer lands in its own,
            // marked unread there, and that chat leaves memory once it's written.
            if (root.sessions.some(x => x.id === sid)) {
                const c = root.hold(sid);
                const msgs = c.messages.concat([msg]);
                root.held = Object.assign({}, root.held, { [sid]: { messages: msgs, summary: c.summary, summaryUpTo: c.summaryUpTo } });
                root.patchSession(sid, { count: msgs.length, updatedAt: Date.now() });
                root.markDirty(sid);
                root.release(sid);
                const u = Object.assign({}, root.unread); u[sid] = true; root.unread = u;
            }
        }
    }

    // ── Block rendering (kuwai-render --serve) ─────────────────────────
    // Answers render block by block (Turn.splitBlocks): one kuwai-render turns
    // each block into Qt rich text in ~1 ms, cached by its text. A finished
    // block never changes, so it renders once; the block being written
    // re-renders as it grows. Messages store no HTML.
    // It runs only around the chat: started when the assistant opens (warm
    // before the first block: a cold start is 50–65 ms to the first reply,
    // 340 ms once on a loaded machine), or by the first block asked for, and
    // stopped once the assistant is closed and nothing has been rendered for
    // 3 minutes (reopening to read the answer again stays warm). The HTML
    // already made stays here, so a stop costs nothing on screen.
    // The HTML is bounded (Caches.htmlPut): a block's half-written versions go
    // as soon as a longer one or the finished block arrives, and the rest is
    // capped at ~4 MB of text and 1,500 blocks, oldest first.
    property var htmlCache: Caches.htmlCache()
    property var renderWaiting: ({})     // key → true while in flight
    property var renderKeys: ({})        // request id → block
    property int renderTick: 0           // bumps when a block's HTML arrives

    function blockKey(b) { return Caches.blockKey(b); }
    // The block's HTML, or "" while it's being rendered (it asks for it).
    function blockHtml(b) {
        if (!b || !b.text) return "";
        const k = blockKey(b);
        const h = Caches.htmlGet(htmlCache, b);
        if (h !== undefined) return h;
        if (!renderWaiting[k]) {
            renderWaiting[k] = true;
            // Not ++renderSeq: blockHtml runs inside the chat's bindings, and writing a
            // property a binding just read loops it (Qt warned: binding loop on "html").
            const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
            renderKeys[id] = { kind: b.kind, lang: b.lang || "", text: b.text, live: !!b.live };
            if (!renderProc.running) renderProc.running = true;
            renderIdle.restart();
            renderProc.write(JSON.stringify({ id: id, kind: b.kind, lang: b.lang || "", text: b.text, live: !!b.live }) + "\n");
        }
        return "";
    }

    Process {
        id: renderProc
        // Dies with the shell. A kill -9 otherwise leaves the renderer behind.
        command: ["setpriv", "--pdeathsig", "KILL", "--", Paths.bin + "/kuwai-render", "--serve"]
        stdinEnabled: true
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                let r;
                try { r = JSON.parse(line); } catch (e) { return; }
                const b = root.renderKeys[r.id];
                delete root.renderKeys[r.id];
                if (b === undefined) return;
                delete root.renderWaiting[Caches.blockKey(b)];
                Caches.htmlPut(root.htmlCache, b, r.html || "", Date.now());
                root.renderTick++;
            }
        }
        // It restarts on the next request if it ever dies; anything in flight asks again.
        onExited: { root.renderWaiting = ({}); root.renderKeys = ({}); root.renderTick++; }
    }
    Timer {
        id: renderIdle
        interval: 180000
        onTriggered: {
            if (Assistant.open || Object.keys(root.renderKeys).length > 0) restart();
            else renderProc.running = false;
        }
    }
    Connections {
        target: Assistant
        function onOpenChanged() {
            if (Assistant.open) { if (!renderProc.running) renderProc.running = true; renderIdle.restart(); }
        }
    }

    // ── Searching the chats (the sidebar) ─────────────────────────────
    // Titles, the open chat and held ones are searched in memory; the rest in
    // their files by `kuwai-ollama find` (after a pause in typing), so their
    // messages needn't be loaded. `q` is lower-case and trimmed.
    property string searchQuery: ""
    property string searchFor: ""          // the query searchHits answer
    property var searchHits: ({})          // id → snippet, for chats not in memory
    function searchChats(q) {
        const t = String(q || "").toLowerCase().trim();
        root.searchQuery = t;
        if (!t) { searchDelay.stop(); root.searchHits = ({}); root.searchFor = ""; return; }
        searchDelay.restart();
    }
    Timer {
        id: searchDelay
        interval: 150
        onTriggered: {
            root.flush();                  // what's in memory is on disk before the files are read
            finder.q = root.searchQuery;
            finder.command = [root.bin, "find", root.chatDir, root.searchQuery];
            finder.running = false;
            finder.running = true;
        }
    }
    Process {
        id: finder
        property string q: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (finder.q !== root.searchQuery) return;
                let hits = {};
                try { const d = JSON.parse(text); if (d && typeof d === "object" && !Array.isArray(d)) hits = d; } catch (e) {}
                root.searchHits = hits;
                root.searchFor = finder.q;
            }
        }
    }
    function chatInMemory(id) {
        return id === root.activeSessionId ? root.messages : (root.held[id] ? root.held[id].messages : null);
    }
    function chatMatches(s, q) {
        if (!q) return true;
        if ((s.title || "").toLowerCase().indexOf(q) >= 0) return true;
        const mem = root.chatInMemory(s.id);
        if (mem) return ChatStore.searchMessages(mem, q).found;
        return root.searchFor === q && root.searchHits[s.id] !== undefined;
    }
    // Where the search hit in a chat's messages (not its title): ~70 characters around it.
    function chatSnippet(s, q) {
        if (!q || (s.title || "").toLowerCase().indexOf(q) >= 0) return "";
        const mem = root.chatInMemory(s.id);
        if (mem) return ChatStore.searchMessages(mem, q).snippet;
        return root.searchFor === q ? String(root.searchHits[s.id] || "") : "";
    }

    // ── Copy chat as Markdown ─────────────────────────────────────────
    function copyChat() {
        const sess = root.sessions.find(x => x.id === root.activeSessionId);
        Clipboard.copyText(Turn.chatMarkdown(sess ? sess.title : "Chat", root.messages));
    }

    IpcHandler {
        target: "ollama"
        function send(prompt: string) { root.send(prompt); }
        function model(): string { return root.model; }
        function setModel(m: string) { root.model = m; }
        function count(): int { return root.messages.length; }
        function isStreaming(): bool { return root.streaming; }
        function setPendingImage(img: string) { root.pendingImage = img; }
        function pendingImage(): string { return root.pendingImage; }
        function newChat() { root.newChat(); }
        function cancel() { root.cancel(); }
        function steer(text: string) { root.steer(text); }
        function attach(path: string) { root.attach(path); }
        function setMode(m: string) { root.mode = m === "agent" ? "agent" : "chat"; root.syncCurrentSession(); }
        function mode(): string { return root.mode; }
        function fork(index: int, model: string) { root.forkAt(index, model); }
        function enqueue(text: string) { root.enqueue(text); }
        function queue(): string { return JSON.stringify(root.queue.map(q => q.text)); }
        function summary(): string { return JSON.stringify({ summary: root.summary, upTo: root.summaryUpTo, count: root.messages.length }); }
        function clearPending() { root.pendingImage = ""; root.pendingContext = null; root.pendingAppTitle = ""; }
        // No resolveRequest / answer here: any program running as you can call IPC, and approvals
        // (ids are q1, q2, …) must come from you in the panel (red-team 9). Declining stays possible.
        function decline() { if (root.pendingRequest) root.resolveRequest(root.pendingRequest.id, "decline", ""); }
        function draft(): string { return root.draft ? JSON.stringify(root.draft) : ""; }
        function switchSession(id: string) { root.switchSession(id); }
        function deleteSession(id: string) { root.deleteSession(id); }
        // Which chats' messages are in memory (the open one, and any a turn is answering in).
        function inMemory(): string { return JSON.stringify([root.activeSessionId].concat(Object.keys(root.held))); }
        function lastMessage(): string {
            if (root.messages.length === 0) return "";
            return JSON.stringify(root.messages[root.messages.length - 1]);
        }
    }
}
