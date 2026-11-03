pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import "ai/turn.mjs" as Turn

// The assistant's state. Turns run in bin/rice_agent.py (`rice-ollama agent`),
// which prints events; Turn.applyEvent folds them into `draft`, an assistant
// message made of parts (reasoning, tools, text). See
// docs/superpowers/plans/2026-11-03-assistant-agent-parity.md.
Singleton {
    id: root

    readonly property string bin: Quickshell.env("HOME") + "/Projects/rice/bin/rice-ollama"
    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID"))) + "/rice/ai"
    readonly property string reqPath: runtimeDir + "/request.json"

    property string status: "offline" // "ready" | "loading" | "offline"
    property string model: "hermes3:8b"
    property var availableModels: ["hermes3:8b", "minicpm-v:latest"]
    property var runningModels: []
    // From `rice-ollama status`: { name: { capabilities: [...], sizeGb, params } }.
    property var modelInfo: ({})

    function hasCap(m, cap) {
        const i = modelInfo[m];
        return !!i && (i.capabilities || []).indexOf(cap) >= 0;
    }
    function isLoaded(m) { return runningModels.some(r => r.name === m); }
    property bool streaming: false

    // The assistant message being streamed (Turn.newAssistant shape), or null.
    property var draft: null
    // Drop the draft when the turn ends (new chat / switch / clear mid-turn).
    property bool discardDraft: false
    property string draftSessionId: ""

    readonly property var pendingRequest: Turn.pendingRequest(draft)

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
    // Sessions: [{ id: string, title: string, model: string, messages: array, updatedAt: number }]
    property var sessions: []
    property string activeSessionId: ""

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
        root.queue = root.queue.concat([{ id: newId("q-"), text: t, image: root.pendingImage, context: root.pendingContext }]);
        root.pendingImage = ""; root.pendingContext = null; root.pendingAppTitle = "";
    }

    function steer(text) {
        const t = (text || "").trim();
        if (!t) return;
        // A steer is words only; with a screenshot or context attached it waits its turn.
        if (!streaming || !chatProc.running || chatProc.sawTurnEnd || pendingImage || pendingContext) { enqueue(t); return; }
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
        if (streaming && !q.image && !q.context) { removeQueued(id); steer(q.text); return; }
        if (streaming) return;
        removeQueued(id);
        root.pendingImage = q.image || ""; root.pendingContext = q.context || null;
        send(q.text || "Look at this.");
    }

    Timer {
        id: drainTimer
        interval: 350
        onTriggered: if (!root.streaming && root.queue.length > 0) root.sendQueuedNow(root.queue[0].id)
    }

    // Compaction (bin/rice_agent.py `compact`): a note standing in for
    // messages[0 .. summaryUpTo), kept with the chat.
    property string summary: ""
    property int summaryUpTo: 0
    readonly property real compactAt: 0.75      // of the context window

    // Tokens the last turn used (prompt + answer) against the window it ran with.
    readonly property int contextUsed: lastStats ? (lastStats.promptEvalCount || 0) + (lastStats.evalCount || 0) : 0
    readonly property int contextTotal: lastStats ? (lastStats.numCtx || 4096) : 4096

    function modelLabel(m) {
        if (!m) return "";
        const base = m.split(":")[0];
        const known = { "hermes3": "Hermes 3", "deepseek-r1": "DeepSeek R1", "minicpm-v": "MiniCPM-V",
                        "qwen3": "Qwen 3", "llama3.2": "Llama 3.2", "llama3.1": "Llama 3.1", "gemma3": "Gemma 3" };
        const tag = m.indexOf(":") >= 0 ? m.split(":")[1] : "";
        const size = /^\d+(\.\d+)?b$/i.test(tag) ? " " + tag.toUpperCase() : "";
        return (known[base] || base) + size;
    }

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
            html: m.html || "",
            time: m.time || root.formatTime(msg.timestamp)
        });
        delete out.tools;
        delete out.reasoning;
        delete out.tokensPerSec;
        return out;
    }

    // ── Persistent Sessions Store ─────────────────────────────────────
    FileView {
        id: sessionStore
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rice/ai-sessions.json"
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (Array.isArray(parsed) && parsed.length > 0) {
                    parsed.forEach(s => { s.messages = (s.messages || []).map(root.withParts); });
                    root.sessions = parsed;
                    const first = parsed[0];
                    root.activeSessionId = first.id;
                    root.messages = first.messages || [];
                    root.summary = first.summary || "";
                    root.summaryUpTo = first.summaryUpTo || 0;
                    if (first.model) root.model = first.model;
                }
            } catch (e) {}
            root.ensureInitialSession();
            root.storeLoaded = true;
        }
        onLoadFailed: {
            root.ensureInitialSession();
            root.storeLoaded = true;
        }
    }

    Timer {
        id: saveDelay
        interval: 400
        onTriggered: {
            if (root.storeLoaded) {
                sessionStore.setText(JSON.stringify(root.sessions, null, 2));
            }
        }
    }

    function formatTime(timestamp) {
        if (!timestamp) return "";
        const d = new Date(timestamp);
        return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }

    function ensureInitialSession() {
        if (root.sessions.length === 0) {
            const initId = Date.now().toString();
            root.sessions = [{
                id: initId,
                title: "New Chat",
                model: root.model,
                messages: [],
                updatedAt: Date.now()
            }];
            root.activeSessionId = initId;
            root.messages = [];
        }
    }

    function newChat() {
        if (streaming) abandon();
        const newId = Date.now().toString();
        const newSess = {
            id: newId,
            title: "New Chat",
            model: root.model,
            messages: [],
            updatedAt: Date.now()
        };
        if (root.messages.length > 0) {
            root.sessions = [newSess, ...root.sessions];
        } else if (root.sessions.length > 0) {
            root.sessions[0] = newSess;
        } else {
            root.sessions = [newSess];
        }
        root.activeSessionId = newId;
        root.queue = [];
        root.messages = [];
        root.summary = "";
        root.summaryUpTo = 0;
        root.lastStats = null;
        root.pendingImage = "";
        root.pendingContext = null;
        root.pendingAppTitle = "";
        root.errorText = "";
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

        if (found) {
            found.execute();
        } else {
            Quickshell.execDetached([appQuery]);
        }

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
        saveDelay.restart();
        return true;
    }

    function recordToolLaunch(appName) {
        return launchApp(appName);
    }

    function switchSession(id) {
        if (id === root.activeSessionId) return;
        if (streaming) abandon();
        root.queue = [];

        syncCurrentSession();

        const found = root.sessions.find(s => s.id === id);
        if (found) {
            root.activeSessionId = id;
            root.messages = found.messages || [];
            root.summary = found.summary || "";
            root.summaryUpTo = found.summaryUpTo || 0;
            root.lastStats = null;
            if (found.model) root.model = found.model;
            root.pendingImage = "";
            root.errorText = "";
        }
    }

    function deleteSession(id) {
        if (streaming && root.activeSessionId === id) abandon();

        const filtered = root.sessions.filter(s => s.id !== id);
        root.sessions = filtered;

        if (root.activeSessionId === id) {
            if (filtered.length > 0) {
                root.activeSessionId = filtered[0].id;
                root.messages = filtered[0].messages || [];
                root.summary = filtered[0].summary || "";
                root.summaryUpTo = filtered[0].summaryUpTo || 0;
                if (filtered[0].model) root.model = filtered[0].model;
            } else {
                ensureInitialSession();
            }
        }
        saveDelay.restart();
    }

    function syncCurrentSession() {
        const idx = root.sessions.findIndex(s => s.id === root.activeSessionId);
        if (idx >= 0) {
            const curr = Object.assign({}, root.sessions[idx]);
            curr.messages = root.messages;
            curr.summary = root.summary;
            curr.summaryUpTo = root.summaryUpTo;
            curr.model = root.model;
            curr.updatedAt = Date.now();
            const updated = [...root.sessions];
            updated[idx] = curr;
            root.sessions = updated;
            saveDelay.restart();
        }
    }

    function clear() {
        if (streaming) abandon();
        root.queue = [];
        root.messages = [];
        root.summary = "";
        root.summaryUpTo = 0;
        root.pendingImage = "";
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
        discardDraft = true;
        cancel();
    }

    function resolveRequest(id, decision) {
        if (!chatProc.running) return;
        chatProc.write(JSON.stringify({ type: "request.resolve", id: id, decision: decision }) + "\n");
    }

    // ── Status Probing ────────────────────────────────────────────────
    function probe() {
        if (!probeProc.running) {
            probeProc.running = true;
        }
    }

    Timer {
        id: probeTimer
        interval: 12000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.probe()
    }

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
        if (!streaming && unloadProc) {
            unloadProc.running = false;
            unloadProc.running = true;
        }
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
                            cwd: data.cwd || "", git: data.git || null,
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
        if (!promptText || promptText.trim() === "" || streaming) return;

        const trimmedPrompt = promptText.trim();
        // Check for slash commands or direct app launches
        if (trimmedPrompt.startsWith("/open ") || trimmedPrompt.startsWith("/launch ")) {
            const appQuery = trimmedPrompt.replace(/^\/(open|launch)\s+/, "").trim();
            launchApp(appQuery);
            return;
        } else if (trimmedPrompt === "/clear") {
            clear();
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
        if (idx >= 0 && (root.sessions[idx].title === "New Chat" || root.messages.length === 0)) {
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
    function startTurn() {
        errorText = "";
        root.discardDraft = false;
        root.draftSessionId = root.activeSessionId;
        root.draft = Turn.newAssistant(root.model, Date.now());
        root.streaming = true;

        const sent = Turn.toApiMessagesWithIndex(root.messages.slice(root.summaryUpTo), root.summaryUpTo);
        // Compact when the last turn filled 3/4 of the window, or the history
        // looks that big (≈4 characters a token, plus ~900 for the system prompt and tools).
        const chars = sent.api.reduce((n, m) => n + (m.content || "").length, root.summary.length);
        const estimate = chars / 4 + 900;
        const compact = Math.max(root.contextUsed, estimate) >= root.compactAt * 4096;
        chatProc.sentIndex = sent.index;
        chatProc.sentUpTo = root.summaryUpTo;

        reqFileWriter.setText(JSON.stringify({
            model: root.model,
            messages: sent.api,
            summary: root.summary,
            compact: compact,
            keep_alive: "5m",
            options: { num_ctx: 4096, temperature: root.model.indexOf("hermes") >= 0 ? 0.4 : 0.7 }
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
                root.draft = Turn.applyEvent(root.draft, ev);
                if (ev.type === "item.completed" && ev.status === "completed" && root.draft) {
                    const p = root.draft.parts.find(q => q.id === ev.id);
                    if (p && p.itemType === "context_compaction" && root.draftSessionId === root.activeSessionId) {
                        root.summary = ev.output || "";
                        root.summaryUpTo = Turn.compactedUpTo(chatProc.sentUpTo, chatProc.sentIndex, (p.input || {}).kept || 0);
                        root.syncCurrentSession();
                    }
                }
                if (ev.type === "turn.steered") root.steering = root.steering.filter(x => x.id !== ev.id);
                if (ev.type === "turn.completed") {
                    // Steers it couldn't take (and any still in flight) wait at the front of the queue.
                    const back = (ev.unapplied || []).concat(root.steering)
                        .filter((x, i, a) => a.findIndex(y => y.id === x.id) === i)
                        .map(x => ({ id: x.id, text: x.text, image: "", context: null }));
                    if (back.length) root.queue = back.concat(root.queue);
                    root.steering = [];
                    root.drainAfterTurn = ev.status === "completed" || ev.status === "max_tool_rounds" || ev.status === "repeating";
                    chatProc.sawTurnEnd = true;
                    root.lastStats = ev.stats || null;
                    if (ev.status === "failed") root.errorText = ev.error || "The turn failed.";
                }
            }
        }
        onExited: exitCode => {
            if (!chatProc.sawTurnEnd && !root.discardDraft && root.errorText === "") {
                root.errorText = "The assistant stopped unexpectedly (exit " + exitCode + ").";
            }
            root.finishTurn();
        }
    }

    // The draft becomes a message in the chat it was started in.
    function finishTurn() {
        const d = root.draft;
        const keep = d && !root.discardDraft && d.parts.length > 0;
        root.streaming = false;
        root.draft = null;
        if (root.discardDraft) { root.queue = []; root.steering = []; }
        root.discardDraft = false;
        if (root.drainAfterTurn && root.queue.length > 0) drainTimer.restart();
        root.drainAfterTurn = false;
        if (!keep) return;

        const msg = root.withParts(Object.assign({}, d, { time: formatTime(Date.now()) }));
        if (root.draftSessionId === root.activeSessionId) {
            const updated = [...root.messages, msg];
            root.messages = updated;
            root.syncCurrentSession();
            // Markdown for the last text part (the answer); earlier ones are short lead-ins.
            const texts = msg.parts.filter(p => p.kind === "text");
            if (texts.length) root.renderMessage(updated.length - 1, texts[texts.length - 1].text);
        }
    }

    // ── Rich Text Markdown Rendering ──────────────────────────────────
    // The answer's Markdown, one segment at a time (prose / fenced code, see
    // Turn.splitFences), so code blocks get their own header and Copy. Each
    // segment's HTML lands in messages[index].segHtml[i]; older messages keep
    // their one `html`.
    function renderMessage(index, rawText) {
        if (!rawText || rawText.trim() === "") return;
        const segs = Turn.splitFences(rawText);
        segs.forEach((seg, i) => {
            // Code goes in bare (rice-render detects and highlights it); fenced, it highlights the fences too.
            const source = seg.text;
            const file = root.runtimeDir + "/render_" + index + "_" + i + ".md";
            renderProcComponent.createObject(root, { msgIndex: index, segIndex: i, segCount: segs.length, filePath: file, source: source, isCode: seg.kind === "code" });
        });
    }

    Component {
        id: renderProcComponent
        Process {
            id: rProc
            property int msgIndex: -1
            property int segIndex: 0
            property int segCount: 1
            property string filePath: ""
            property string source: ""
            property bool isCode: false
            command: [root.bin, "render", filePath]
            // Each run writes its own file first (one shared writer would race).
            property FileView writer: FileView { path: rProc.filePath; blockWrites: true; printErrors: false }
            Component.onCompleted: { writer.setText(source); running = true; }
            stdout: StdioCollector {
                onStreamFinished: {
                    const out = text.trim();
                    if (!out || rProc.msgIndex < 0 || rProc.msgIndex >= root.messages.length) return;
                    try {
                        const parsed = JSON.parse(out);
                        if (!parsed.html) return;
                        // Code: just the highlighted <pre>; our block draws the frame (rice-render's table draws a second one).
                        let html = parsed.html;
                        if (rProc.isCode) {
                            const pre = /<pre[\s\S]*<\/pre>/.exec(html);
                            html = pre ? pre[0] : "";
                            if (!html) return;
                        }
                        const msgs = [...root.messages];
                        const m = Object.assign({}, msgs[rProc.msgIndex]);
                        const seg = (m.segHtml || []).slice();
                        while (seg.length < rProc.segCount) seg.push("");
                        seg[rProc.segIndex] = html;
                        m.segHtml = seg;
                        msgs[rProc.msgIndex] = m;
                        root.messages = msgs;
                        root.syncCurrentSession();
                    } catch (e) {}
                }
            }
            onExited: destroy(500)
        }
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
        function enqueue(text: string) { root.enqueue(text); }
        function queue(): string { return JSON.stringify(root.queue.map(q => q.text)); }
        function summary(): string { return JSON.stringify({ summary: root.summary, upTo: root.summaryUpTo, count: root.messages.length }); }
        function clearPending() { root.pendingImage = ""; root.pendingContext = null; root.pendingAppTitle = ""; }
        function resolveRequest(id: string, decision: string) { root.resolveRequest(id, decision); }
        function draft(): string { return root.draft ? JSON.stringify(root.draft) : ""; }
        function switchSession(id: string) { root.switchSession(id); }
        function deleteSession(id: string) { root.deleteSession(id); }
        function lastMessage(): string {
            if (root.messages.length === 0) return "";
            return JSON.stringify(root.messages[root.messages.length - 1]);
        }
    }
}
