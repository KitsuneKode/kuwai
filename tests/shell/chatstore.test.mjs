// The assistant keeps one chat's messages in memory, not all of them, and
// nothing is lost on the way: the old one-file store splits into chat files,
// every chat round-trips through its file, a failed write keeps the chat in
// memory, and chat files the list lost come back. ChatStore's rules, then
// OllamaService.qml's own functions over a fake disk.
// `bun test tests/shell/chatstore.test.mjs`
import { describe, expect, test } from "bun:test";
import * as ChatStore from "../../shell/services/ai/chatstore.mjs";
import * as Turn from "../../shell/services/ai/turn.mjs";
import { functions } from "../helpers/qml.mjs";

const STATE = "/state/kuwai";
const DIR = STATE + "/ai-chats";
const INDEX = STATE + "/ai-sessions.json";

const user = (text, t) => ({ role: "user", text, image: "", context: null, time: "", timestamp: t, model: "m" });
const answer = (text, t) => ({ role: "assistant", model: "m", timestamp: t, status: "completed", stats: null, error: "", text, time: "t",
  parts: [{ id: "x" + t, kind: "text", itemType: "assistant_message", title: "", input: null, text, output: "", status: "completed", request: null, startedAt: 0, endedAt: 0 }] });

describe("ChatStore", () => {
  test("the old one-file store reads as legacy, with a file's worth for each chat", () => {
    const old = JSON.stringify([
      { id: "200", title: "B", model: "m", mode: "agent", renamed: true, updatedAt: 2, summary: "s", summaryUpTo: 1, messages: [user("hi", 1), answer("yo", 2)] },
      { id: "100", title: "A", model: "m", updatedAt: 1, messages: [] },
      { id: "../etc/passwd", title: "evil", messages: [user("x", 1)] },
    ]);
    const r = ChatStore.readIndex(old);
    expect(r.kind).toBe("legacy");
    expect(r.chats.map(c => [c.id, c.count, c.mode])).toEqual([["200", 2, "agent"], ["100", 0, "chat"]]);
    expect(r.chats[0].renamed).toBe(true);
    expect(r.docs[0].summary).toBe("s");
    expect(r.docs[0].messages.length).toBe(2);
    expect(r.chats[0]).not.toHaveProperty("messages");
  });
  test("v2 round-trips; garbage, a later version and nothing are told apart", () => {
    const chats = [ChatStore.metaOf({ id: "1", title: "T", model: "m", updatedAt: 5 }, 3)];
    const r = ChatStore.readIndex(ChatStore.indexText(chats));
    expect(r.kind).toBe("v2");
    expect(r.chats).toEqual(chats);
    expect(ChatStore.readIndex("{not json").kind).toBe("bad");
    expect(ChatStore.readIndex('{"version":3,"chats":[]}').kind).toBe("newer");
    expect(ChatStore.readIndex("").kind).toBe("empty");
  });
  test("a chat file: what's written is what's read; a cut-short file is not a chat", () => {
    const d = ChatStore.chatDoc({ id: "7", title: "T", updatedAt: 9 }, [user("ü ✓ \"q\"\n", 1)], "sum", 1);
    const text = ChatStore.chatText(d);
    expect(ChatStore.parseChat(text)).toEqual(d);
    expect(ChatStore.parseChat(text.slice(0, text.length - 3))).toBeNull();
    expect(ChatStore.parseChat('{"id":"../x","messages":[]}')).toBeNull();
  });
  test("the split never shrinks a chat already on disk", () => {
    const d = ChatStore.chatDoc({ id: "7" }, [user("a", 1)], "", 0);
    const longer = ChatStore.chatText(ChatStore.chatDoc({ id: "7" }, [user("a", 1), answer("b", 2)], "", 0));
    expect(ChatStore.shouldWriteLegacy("", d)).toBe(true);
    expect(ChatStore.shouldWriteLegacy(longer, d)).toBe(false);
    expect(ChatStore.shouldWriteLegacy("garbage", d)).toBe(true);
  });
  test("ids that aren't plain never become paths", () => {
    for (const bad of ["", "..", "../x", "a/b", "a b", "x".repeat(65), 5, null]) expect(ChatStore.chatPath(DIR, bad)).toBe("");
    expect(ChatStore.chatPath(DIR, "1731800000000")).toBe(DIR + "/1731800000000.json");
  });
  test("search: the same snippet the sidebar always cut", () => {
    const msgs = [user("first message", 1), answer("Here is   a   long\nanswer about the quarterly numbers and what they mean for you", 2)];
    expect(ChatStore.searchMessages(msgs, "quarterly")).toEqual({ found: true, snippet: "…a long answer about the quarterly numbers and what they mean for you" });
    expect(ChatStore.searchMessages(msgs, "nothing").found).toBe(false);
  });
});

// ── OllamaService.qml's store, over a fake disk ─────────────────────────────
const NAMES = ["openStore", "splitLegacy", "docsById", "adoptOrphans", "loadChat", "contentOf", "hold", "release", "leave", "markDirty",
  "writeChat", "flush", "ensureInitialSession", "newChat", "forkAt", "switchSession", "renameSession", "deleteSession", "patchSession",
  "syncCurrentSession", "sendIn", "startTurn", "finishTurn", "withParts", "chatInMemory", "chatMatches", "chatSnippet"];

function service(disk, opts) {
  const o = opts || {};
  const writes = [];
  const s = functions("shell/services/OllamaService.qml", NAMES, {
    ChatStore, Turn, console: { warn() {} },
    stateDir: STATE, chatDir: DIR,
    sessions: [], messages: [], summary: "", summaryUpTo: 0, activeSessionId: "", held: {}, dirty: {}, indexDirty: false,
    storeLoaded: false, legacyDocs: null, streaming: false, draftSessionId: "", discardDraft: false, draft: null,
    model: "m", mode: "chat", lastStats: null, pendingImage: "", pendingContext: null, pendingAppTitle: "", errorText: "",
    unread: {}, queue: [], steering: [], drainAfterTurn: false, compactNext: false, contextUsed: 0, compactAt: 0.75,
    contextFor: () => 16384, formatTime: () => "12:00",
    flushDeltas() {}, notifyDone() {}, abandon() {},
    drainTimer: { restart() {} }, saveDelay: { restart() {} }, sessionBackup: { setText() {} },
    reqFileWriter: { setText() {} }, chatProc: { running: false },
    orphanScan: { set running(v) { if (v) s.adoptOrphans(Object.keys(disk).filter(p => p.startsWith(DIR + "/")).map(p => p.slice(DIR.length + 1)).join("\n")); } },
    sessionStore: { setText(t) { writes.push(INDEX); disk[INDEX] = t; } },
    readFile: p => disk[p] || "",
    writeFile(p, t) { if (o.failWrite && o.failWrite(p)) return false; writes.push(p); disk[p] = t; return true; },
    removeChatFile(id) { delete disk[ChatStore.chatPath(DIR, id)]; },
  });
  s.writes = writes;
  return s;
}
const inMemory = s => [s.activeSessionId].concat(Object.keys(s.held));
const chatOnDisk = (disk, id) => ChatStore.parseChat(disk[ChatStore.chatPath(DIR, id)] || "");

function legacyStore(n, perChat) {
  const chats = [];
  for (let i = 0; i < n; i++) {
    const id = String(1700000000000 + i);
    const msgs = [];
    for (let k = 0; k < perChat; k++) msgs.push(k % 2 ? answer("answer " + i + "." + k, k) : user("question " + i + "." + k, k));
    chats.push({ id, title: "Chat " + i, model: "m", mode: i % 3 ? "chat" : "agent", updatedAt: 1000 + i, summary: i % 5 ? "" : "sum " + i, summaryUpTo: i % 5 ? 0 : 2, messages: msgs });
  }
  return chats;
}

describe("OllamaService store", () => {
  test("an old store splits into chat files once; only the first chat is in memory; every chat round-trips", () => {
    const old = legacyStore(40, 6);
    const disk = { [INDEX]: JSON.stringify(old, null, 2) };
    const s = service(disk);
    s.openStore(disk[INDEX]);
    expect(s.storeLoaded).toBe(true);
    expect(disk[STATE + "/ai-sessions.legacy.json"]).toBe(JSON.stringify(old, null, 2));   // the original, aside
    expect(ChatStore.readIndex(disk[INDEX]).kind).toBe("v2");
    expect(inMemory(s)).toEqual([old[0].id]);
    expect(s.sessions.every(c => !("messages" in c))).toBe(true);
    for (const c of old) {
      const d = chatOnDisk(disk, c.id);
      expect(d.messages).toEqual(c.messages);
      expect(d.summary).toBe(c.summary);
      expect(d.summaryUpTo).toBe(c.summaryUpTo);
    }
    // The index is written after every chat file.
    expect(s.writes.lastIndexOf(INDEX)).toBeGreaterThan(Math.max(...old.map(c => s.writes.indexOf(ChatStore.chatPath(DIR, c.id)))));
    // A second start reads the new store: nothing rewritten, same list.
    const again = service(disk);
    again.openStore(disk[INDEX]);
    expect(again.writes).toEqual([]);
    expect(again.sessions.map(c => c.id)).toEqual(old.map(c => c.id));
    expect(again.messages.map(m => m.text)).toEqual(old[0].messages.map(m => m.text));
  });

  test("if a chat file can't be written, the old store is left as it was and nothing is saved", () => {
    const old = legacyStore(5, 2);
    const text = JSON.stringify(old);
    const disk = { [INDEX]: text };
    const s = service(disk, { failWrite: p => p.endsWith(old[3].id + ".json") });
    s.openStore(text);
    expect(s.storeLoaded).toBe(false);
    expect(disk[INDEX]).toBe(text);
    // Chats still open from the old file.
    s.switchSession(old[3].id);
    expect(s.messages.map(m => m.text)).toEqual(old[3].messages.map(m => m.text));
    s.flush();
    expect(disk[INDEX]).toBe(text);
  });

  test("a long run: 300 chats, 3,000 switches and sends, never more than two in memory, and all of it on disk", () => {
    const disk = {};
    const s = service(disk);
    s.openStore("");
    const want = {};                       // id → texts, the truth
    let clock = 1;
    for (let i = 0; i < 300; i++) {
      s.newChat();
      s.activeSessionId = String(1800000000000 + i);   // newChat's Date.now() ids can collide in a fast loop
      s.sessions = [Object.assign({}, s.sessions[0], { id: s.activeSessionId })].concat(s.sessions.slice(1));
      s.messages = [user("hello " + i, clock++)];
      s.syncCurrentSession();
      want[s.activeSessionId] = ["hello " + i];
    }
    let seed = 7;
    const rnd = n => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
    let worst = 0;
    for (let k = 0; k < 3000; k++) {
      const id = s.sessions[rnd(s.sessions.length)].id;
      s.switchSession(id);
      expect(s.messages.map(m => m.text)).toEqual(want[id]);
      const t = "msg " + k;
      s.messages = s.messages.concat([user(t, clock++)]);
      s.syncCurrentSession();
      want[id].push(t);
      if (k % 10 === 0) s.flush();
      worst = Math.max(worst, inMemory(s).length);
    }
    s.flush();
    expect(worst).toBeLessThanOrEqual(1);
    // Restart from what's on disk: every chat, every message.
    const again = service(disk);
    again.openStore(disk[INDEX]);
    for (const id of Object.keys(want)) {
      expect(chatOnDisk(disk, id).messages.map(m => m.text)).toEqual(want[id]);
      expect(again.sessions.find(c => c.id === id).count).toBe(want[id].length);
    }
  });

  test("a turn answering in a chat you left keeps it in memory until the answer is written, then lets it go", () => {
    const disk = {};
    const s = service(disk);
    s.openStore(JSON.stringify(legacyStore(3, 2)));
    const [a, b] = s.sessions.map(c => c.id);
    s.messages = s.messages.concat([user("long question", 9)]);
    s.syncCurrentSession();
    s.startTurn();
    expect(s.streaming).toBe(true);
    s.switchSession(b);
    expect(inMemory(s).sort()).toEqual([a, b].sort());
    s.draft = Turn.applyEvent(s.draft, { type: "item.delta", id: "t1", text: "the answer" });
    s.draft = Object.assign({}, s.draft, { parts: [{ id: "t1", kind: "text", text: "the answer", status: "completed" }], status: "completed" });
    s.finishTurn();
    expect(inMemory(s)).toEqual([b]);
    expect(s.unread[a]).toBe(true);
    const d = chatOnDisk(disk, a);
    expect(d.messages.map(m => Turn.textOf(m) || m.text)).toEqual(["question 0.0", "answer 0.1", "long question", "the answer"]);
    expect(s.sessions.find(c => c.id === a).count).toBe(4);
  });

  test("a queued message for a chat you left runs there and doesn't stay loaded", () => {
    const disk = {};
    const s = service(disk);
    s.openStore(JSON.stringify(legacyStore(3, 2)));
    const c = s.sessions[2].id;
    s.sendIn({ session: c, text: "later", image: "", context: null });
    expect(s.draftSessionId).toBe(c);
    expect(Object.keys(s.held)).toEqual([c]);
    s.draft = Object.assign({}, s.draft, { parts: [{ id: "t", kind: "text", text: "done", status: "completed" }], status: "completed" });
    s.finishTurn();
    expect(Object.keys(s.held)).toEqual([]);
    expect(chatOnDisk(disk, c).messages.length).toBe(4);
  });

  test("leaving a chat whose file can't be written keeps it in memory; the next save writes it and lets go", () => {
    const disk = {};
    let failing = true;
    const s = service(disk, { failWrite: p => failing && p.endsWith(".json") && p.startsWith(DIR) });
    failing = false;
    s.openStore(JSON.stringify(legacyStore(3, 2)));
    failing = true;
    const [a, b] = s.sessions.map(c => c.id);
    s.messages = s.messages.concat([user("don't lose me", 5)]);
    s.syncCurrentSession();
    s.switchSession(b);
    expect(Object.keys(s.held)).toEqual([a]);
    failing = false;
    s.flush();
    expect(Object.keys(s.held)).toEqual([]);
    expect(chatOnDisk(disk, a).messages.map(m => m.text)).toContain("don't lose me");
  });

  test("chat files the list doesn't name come back (an older shell rewrote the list)", () => {
    const disk = {};
    const s = service(disk);
    s.openStore(JSON.stringify(legacyStore(4, 2)));
    disk[INDEX] = JSON.stringify([{ id: "1900000000000", title: "New Chat", model: "m", messages: [] }]);   // what an old shell writes
    const again = service(disk);
    again.openStore(disk[INDEX]);
    expect(again.sessions.map(c => c.id).sort()).toEqual(["1700000000000", "1700000000001", "1700000000002", "1700000000003", "1900000000000"]);
    expect(chatOnDisk(disk, "1700000000002").messages.length).toBe(2);         // the split didn't shrink it
  });

  test("delete removes the chat's file; fork writes the new chat", () => {
    const disk = {};
    const s = service(disk);
    s.openStore(JSON.stringify(legacyStore(3, 4)));
    const [a, b] = s.sessions.map(c => c.id);
    s.forkAt(1);
    const f = s.activeSessionId;
    expect(f).not.toBe(a);
    s.flush();
    expect(chatOnDisk(disk, f).messages.length).toBe(2);
    expect(chatOnDisk(disk, a).messages.length).toBe(4);
    s.deleteSession(b);
    expect(disk[ChatStore.chatPath(DIR, b)]).toBeUndefined();
    s.flush();
    expect(ChatStore.readIndex(disk[INDEX]).chats.map(c => c.id)).not.toContain(b);
  });

  test("search finds the open chat in memory and the others through the finder's hits", () => {
    const disk = {};
    const s = service(disk);
    s.openStore(JSON.stringify(legacyStore(3, 2)));
    const [a, b] = s.sessions;
    expect(s.chatMatches(a, "question 0.0")).toBe(true);
    expect(s.chatMatches(b, "question 1.0")).toBe(false);          // not in memory, no hits yet
    s.searchFor = "question 1.0"; s.searchHits = { [b.id]: "question 1.0" };
    expect(s.chatMatches(b, "question 1.0")).toBe(true);
    expect(s.chatSnippet(b, "question 1.0")).toBe("question 1.0");
    expect(s.chatMatches(b, "chat 1")).toBe(true);                  // the title
  });
});
