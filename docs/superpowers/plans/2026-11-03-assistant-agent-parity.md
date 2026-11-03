# Assistant: Local Agent, Tool Calls and Polished UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Super+Ctrl+Shift+A assistant into a local agent on par with the ChatGPT / Claude desktop apps for the
features that matter: real tool calls (shown live, approved when they act), reasoning, vision, message actions, a
real model picker, and motion that follows the rice's tokens everywhere.

**Architecture:** The Python helper `bin/rice-ollama` becomes the agent: it owns the Ollama tool loop and prints one
JSON event per line, using T3 Code's runtime vocabulary (`item.started` / `item.delta` / `item.completed` /
`request.opened` / `turn.completed`). QML stops parsing Ollama: a pure reducer (`shell/services/ai/turn.mjs`) folds
events into a message made of ordered `parts`, and the components render parts. Approvals go back to the helper on
stdin. Because the protocol is provider-neutral, the Codex / Claude backends in `docs/CHAT.md` can emit the same
events later without touching the UI.

**Tech Stack:** Quickshell 0.3.2 (Qt 6 QML), Python 3 stdlib (helper), Ollama 0.40.13 (`/api/chat` with `tools`,
`think`), pytest 9 (helper tests), Bun (`bun test` for the `.mjs` reducer), qmllint.

**Spec:** this file plus the user's request of 2026-11-03 ("full parity with the necessary features of the ChatGPT /
Claude desktop app … tool calls … premium, polished pickers … not AI-generated looking"), the transitions review of
the same day (motion list in Task 11), `docs/DESIGN.md` (material, type, motion rules) and `docs/CHAT.md` (the
longer-term provider plan this stays compatible with).

## Global Constraints

- Motion values come from `shell/config/Theme.qml` only (`enterMs 200`, `exitMs 150`, `pressMs 140`, `colorMs 140`,
  `reflowMs 200`, `easeOut`, `springFast/Moderate/Slow`, `surfaceIn/Out`). No literal durations in new QML.
- Every new motion has a `Theme.reduceMotion` path: fades and colour stay; travel, scale and stagger go.
- Opens on a spring or `enterMs`; closes one tier quicker (`springModerate.exitMs 120`, `springSlow.exitMs 160`), no
  overshoot on a close, never a delay on a close.
- Press feedback: scale `0.97` (rows `0.985`), `Theme.pressMs`, `Theme.easeOut`.
- Helper stays Python stdlib only (no pip deps); runs as `bin/rice-ollama <cmd>`.
- `.mjs` files use what Qt's V4 engine and Bun both accept: ES2017 + spread, no `?.`, no `??`, no top-level await.
- Tools that only read run without asking. Tools that execute, launch or open (run_command, launch_app, open_url)
  emit `request.opened` and wait; no answer in 120 s = `timeout` = declined.
- One model in VRAM at a time (RTX 4050, 6 GB): a vision hop unloads with `keep_alive: 0` before the tool model runs.
- Tool rounds per turn: max 6.
- `refs/` is ideas only: read, then rewrite in our style. Tide-island is GPL-3 (never copy code).
- Copy: sentence case, no "AI-powered", no emoji, no uppercase labels (DESIGN.md). Picker header reads "Model".
- Work on a branch `feat/assistant-agent`; commit per task.

## Review Focus

1. A model without the `tools` capability (minicpm-v) is selected → the turn runs with no `tools` key and answers
   normally; no error. (Task 2, `test_no_tools_for_incapable_model`)
2. The model calls an unknown tool or passes bad arguments → that tool item completes `failed` with a readable error,
   the error goes back to the model, the turn still finishes. (Task 2, `test_unknown_tool_fails_item_not_turn`)
3. The model loops on tools → after 6 rounds the turn ends with `status: "max_tool_rounds"` and whatever text it has.
   (Task 2, `test_tool_round_cap`)
4. Chats saved before this change (text/reasoning/tools fields, no `parts`) open and render unchanged.
   (Task 5, `migrateMessage keeps old text, reasoning and tools`)
5. The overlay is hidden or Stop is pressed while an approval is pending → the helper gets a decline, the item shows
   `declined`, no command runs. (Task 3, `test_cancel_while_pending_declines`; Task 8 manual check)

---

## Phase 0 — References

### Task 0: Record the new references

Already cloned (shallow, gitignored) into `refs/` on 2026-11-03: `vercel_ai-elements`, `ibelick_prompt-kit`,
`assistant-ui_assistant-ui`, `pingdotgg_t3code`, `openai_codex` (sparse: `codex-rs/tui`, `codex-rs/protocol`).

**Files:** Modify: `docs/BORROWING.md` (table + a "Chat / agent UI" pointer section)

- [ ] **Step 1:** Add one table row per ref and these pointers (paths verified):
  - AI Elements `packages/elements/src/`: `tool.tsx` (states: input-streaming → input-available → output), `confirmation.tsx`
    (approval card), `reasoning.tsx`, `chain-of-thought.tsx`, `model-selector.tsx`, `prompt-input.tsx`, `context.tsx`
    (token meter), `queue.tsx`, `task.tsx`, `message.tsx` (actions, branch), `shimmer.tsx`.
  - prompt-kit `components/prompt-kit/`: `scroll-button.tsx`, `chat-container.tsx` (stick-to-bottom), `thinking-bar.tsx`,
    `steps.tsx`, `feedback-bar.tsx`, `tool.tsx`.
  - assistant-ui `packages/core/src/react/primitive-hooks/useActionBar{Copy,Edit,Feedback}.ts`: message action semantics.
  - T3 Code: `packages/contracts/src/providerRuntime.ts` (event + tool item vocabulary we adopt),
    `apps/server/src/orchestration-v2/Adapters/AntigravityAdapterV2.ts` and `provider/acp/AntigravityChildWork.ts` (how
    Antigravity tool calls and sub-agent work are normalised), `apps/web/src/components/chat/` `TimelineAssistantRows.tsx`,
    `TimelinePendingApprovalRow.tsx`, `TimelineToolActivityIcon.tsx`, `ModelPickerContent.tsx`, `ComposerCommandMenu.tsx`.
  - Codex `codex-rs/tui/src/`: `exec_cell/` (how a running command reads), `bottom_pane/approval_overlay.rs`.
- [ ] **Step 2:** Commit `docs: chat/agent references`.

---

## Phase 1 — The agent (helper)

### Task 1: Event protocol and the `agent` command (no tools yet)

**Files:**
- Create: `bin/rice_agent.py` (the agent: loop, tools, events; stdlib only)
- Modify: `bin/rice-ollama` (dispatch `agent` → `rice_agent.main(req_file)`)
- Create: `tests/agent/fake_ollama.py`, `tests/agent/conftest.py`, `tests/agent/test_agent.py`

**Interfaces:**
- Produces (stdout, one JSON object per line):
  - `{"type":"turn.started","model":str}`
  - `{"type":"item.started","id":str,"itemType":ItemType,"title":str,"input":object}` where `ItemType` ∈
    `"reasoning" | "assistant_message" | "command_execution" | "web_search" | "image_view" | "dynamic_tool_call"`
  - `{"type":"item.delta","id":str,"text":str}`
  - `{"type":"item.completed","id":str,"status":"completed"|"failed"|"declined","output":str}`
  - `{"type":"turn.completed","status":"completed"|"interrupted"|"failed"|"max_tool_rounds","error":str,
    "stats":{"evalCount":int,"promptEvalCount":int,"numCtx":int,"tokensPerSec":float}}`
- Request file: `{"model":str,"messages":[{"role","content","image"?}],"options":{"num_ctx":int,"temperature":float},
  "keep_alive":str}`. The helper adds the system prompt (moved here from `OllamaService.send`, same two texts).
- Ids: `"r1"`, `"m1"`, `"t1"`… per turn, kind letter + counter.

- [ ] **Step 1: Fake server.** `fake_ollama.py`: `FakeOllama(script: list[list[dict]])` — a `ThreadingHTTPServer`
  on port 0; each POST `/api/chat` pops the next list and streams it as NDJSON; records request bodies in `.requests`;
  POST `/api/show` returns `{"capabilities": caps[model]}`. `conftest.py` fixture `run_agent(req, script, caps,
  stdin_lines=[]) -> list[dict]` runs `bin/rice-ollama agent <file>` with `OLLAMA_HOST` set and parses stdout.
- [ ] **Step 2: Failing tests.**
  - `test_plain_answer_streams_one_message`: script `[{"message":{"content":"Hel"}},{"message":{"content":"lo"}},
    {"done":true,"eval_count":20,"eval_duration":1e9,"prompt_eval_count":232}]` → event types exactly
    `turn.started, item.started(assistant_message), item.delta, item.delta, item.completed, turn.completed`;
    deltas join to `"Hello"`; `stats.tokensPerSec == 20.0`, `stats.promptEvalCount == 232`.
  - `test_native_thinking_becomes_reasoning_item`: chunks with `message.thinking` → a `reasoning` item started and
    completed before the `assistant_message` item; request body has `"think": true` when caps include `thinking`.
  - `test_think_tags_fallback`: content `"<think>a</think>b"` split across chunks → reasoning text `"a"`, message `"b"`.
  - `test_ollama_down_fails_turn`: no server → single `turn.completed` with `status:"failed"` and non-empty `error`;
    exit code 0.
- [ ] **Step 3: Run** `pytest tests/agent -q` → 4 failures (`agent` unknown).
- [ ] **Step 4: Implement** `cmd_agent`. Capabilities from `POST /api/show {"model"}` → `capabilities` list, cached
  per process. Move the `<think>` scanner from `OllamaService.consumeToken` here.
- [ ] **Step 5: Run** `pytest tests/agent -q` → 4 passed.
- [ ] **Step 6: Commit** `feat(ai): agent event protocol`.

### Task 2: Tool registry, read-only tools, the loop

**Files:** Modify `bin/rice_agent.py`; Test `tests/agent/test_tools.py`; Create `tests/agent/stubs/` (fake `hyprctl`,
`wl-paste`, `gtk-launch`, `xdg-open` scripts that print fixed output; prepended to `PATH` by the fixture).

**Interfaces:**
- `TOOLS: dict[str, Tool]`, `Tool = (schema: dict, item_type: str, needs_approval: bool, run: Callable[[dict], str])`.
- Read-only tools (no approval): `web_search{query}` → itemType `web_search` (reuses `cmd_search` logic, returns
  heading/abstract/url text); `system_info{}` → `dynamic_tool_call` (reuses `cmd_sysinfo`); `active_window{}` →
  `hyprctl activewindow -j` class/title/workspace; `read_clipboard{}` → `wl-paste --no-newline`, text only, 8 KB cap;
  `read_selection{}` → `wl-paste --primary`; `read_file{path}` → under `$HOME` only, text only, 16 KB cap.
- Tool results go back as `{"role":"tool","tool_name":name,"content":output}` after an assistant message carrying
  the `tool_calls` exactly as Ollama sent them (shape verified on 0.40.13: `message.tool_calls[{id,
  function:{index,name,arguments:{…}}}]`, `arguments` is an object).

- [ ] **Step 1: Failing tests.**
  - `test_tool_call_runs_and_answers`: round 1 streams an `active_window` tool call; round 2 streams text →
    events contain `item.started(dynamic_tool_call, title "Active window", input {})`, `item.completed(completed,
    output contains stub's title)`, then an `assistant_message`; second request's messages end with the assistant
    `tool_calls` message and a `role:"tool"` message.
  - `test_no_tools_for_incapable_model`: caps `["completion","vision"]` → request body has no `tools` key.
  - `test_unknown_tool_fails_item_not_turn`: call `rm_everything` → item `failed`, output starts `"Unknown tool"`,
    turn `completed`.
  - `test_tool_round_cap`: 7 rounds of tool calls scripted → exactly 6 tool items, `turn.completed.status ==
    "max_tool_rounds"`.
  - `test_read_file_refuses_outside_home`: `read_file{"path":"/etc/shadow"}` → item `failed`, output mentions home.
- [ ] **Step 2: Run** `pytest tests/agent/test_tools.py -q` → failures.
- [ ] **Step 3: Implement** the registry and loop in `cmd_agent` (send `tools` only when caps include `tools`).
  Titles are human: "Searching the web", "Active window", "Reading clipboard", "Reading ~/path".
- [ ] **Step 4: Run** `pytest tests/agent -q` → all pass.
- [ ] **Step 5: Commit** `feat(ai): read-only tools and tool loop`.

### Task 3: Approval-gated tools and cancel

**Files:** Modify `bin/rice_agent.py`; Test `tests/agent/test_approvals.py`.

**Interfaces:**
- New events: `{"type":"request.opened","id":"q1","itemId":"t1","kind":"command"|"launch"|"open_url",
  "summary":str,"detail":str}` and `{"type":"request.resolved","id":"q1","decision":"accept"|"decline"|"timeout"}`.
- stdin (one JSON per line): `{"type":"request.resolve","id":"q1","decision":"accept"|"decline"}`.
- Tools: `run_command{command, cwd?}` → `command_execution`, runs `bash -lc` with 30 s timeout, output capped 8 KB
  with exit code appended; `launch_app{name}` → `gtk-launch` (desktop id resolved like `OllamaService.findApp`);
  `open_url{url}` → `xdg-open`, http(s) only.
- SIGTERM at any point → pending request resolves `decline`, current item `declined`/`failed`, then
  `turn.completed{status:"interrupted"}`, exit 0.

- [ ] **Step 1: Failing tests.**
  - `test_command_waits_for_accept`: stdin `accept` → order `item.started(command_execution)`, `request.opened`,
    `request.resolved(accept)`, `item.completed(completed)`; stub-free command `echo hi` output contains `hi`.
  - `test_decline_never_runs`: command `touch $TMP/flag`, stdin `decline` → flag file absent, item `declined`, the
    model receives `"The user declined this command."`.
  - `test_timeout_declines`: env `RICE_AGENT_APPROVAL_TIMEOUT=1`, no stdin → `request.resolved(timeout)`, item
    `declined`.
  - `test_cancel_while_pending_declines`: send SIGTERM after `request.opened` is read → flag absent,
    `turn.completed.status == "interrupted"`.
  - `test_open_url_rejects_file_scheme`: `file:///etc/passwd` → item `failed` before any request opens.
- [ ] **Step 2–4:** run (fail) → implement (stdin reader thread + `queue.Queue`, timeout from
  `RICE_AGENT_APPROVAL_TIMEOUT` default 120) → run (pass).
- [ ] **Step 5: Commit** `feat(ai): approval-gated tools, cancel`.

### Task 4: Vision hop ("the snapshot that matters")

**Files:** Modify `bin/rice_agent.py`, `bin/rice-ollama` (`cmd_snapshot`); Test `tests/agent/test_vision.py`.

**Interfaces:**
- If the last user message has `image` and the chosen model lacks `vision`: emit an `image_view` item ("Looking at
  the screenshot"), ask the first installed vision model (caps include `vision`) for a factual description with
  `keep_alive: 0`, then send the tool model the user text plus `"[Screenshot: <description>]"` and no image.
- If the chosen model has `vision`, send the image directly (current behaviour), no hop.
- `rice-ollama snapshot window` additionally returns `selection` (primary selection, 4 KB cap) and `clipboard`
  (text, 4 KB cap) next to `app`, `title`, `path`; the request `messages[-1]` may carry `context: {app,title,
  selection,clipboard}`, which the helper turns into a short "Context" block in the user turn.

- [ ] **Step 1: Failing tests.** `test_vision_hop_for_text_model` (two requests: first to the vision model with
  `images` and `keep_alive:0`, second to hermes without `images`, its last message contains `[Screenshot:`);
  `test_vision_model_gets_image_directly` (one request with `images`); `test_context_block` (context fields appear
  in order App / Window / Selection / Clipboard, empty fields omitted).
- [ ] **Step 2–4:** fail → implement → pass.
- [ ] **Step 5: Commit** `feat(ai): vision hop and snapshot context`.

---

## Phase 2 — State in QML

### Task 5: Turn reducer and the service switch

**Files:**
- Create: `shell/services/ai/turn.mjs`, `shell/services/ai/turn.test.mjs`
- Modify: `shell/services/OllamaService.qml` (chatProc → `agent`, `stdinEnabled: true`; remove `consumeToken`,
  system prompts, Ollama JSON parsing; persist `parts`), `shell/services/Assistant.qml` if it proxies state.

**Interfaces (`turn.mjs`, imported in QML as `import "ai/turn.mjs" as Turn`):**
- `newAssistant(model: string, nowMs: number) -> Msg` — `Msg = {role:"assistant", model, timestamp, status:"streaming",
  parts: Part[], stats: null, error: ""}`
- `applyEvent(msg: Msg, ev: Event) -> Msg` — pure, returns a new object (QML needs new references to notify).
  `Part = {id, kind:"reasoning"|"text"|"tool", itemType, title, input, text, output, status:"running"|"completed"|
  "failed"|"declined", request: null | {id, kind, summary, detail, state:"pending"|"accept"|"decline"|"timeout"}}`.
  `item.started` appends; `item.delta` appends text to that part; `item.completed` sets status/output;
  `request.opened` sets the part's `request` (state pending); `request.resolved` sets its state; `turn.completed`
  sets `status`, `stats`, `error`.
- `migrateMessage(old) -> Msg` — old `{text, reasoning, tools}` → parts `[reasoning?, ...tools, text]`; messages that
  already have `parts` pass through.
- `toApiMessages(msgs: Msg[]) -> {role, content, image?}[]` — prior assistant turns send only their text parts
  joined; tool parts are not replayed.
- `pendingRequest(msg) -> null | {id, partId}`.

- [ ] **Step 1: Failing tests** (`bun test shell/services/ai`): `plain stream builds one text part`; `deltas route
  by id when reasoning and text interleave`; `tool part goes running → completed with output`; `request opened then
  resolved accept`; `turn.completed failed keeps partial text and sets error`; `migrateMessage keeps old text,
  reasoning and tools`; `toApiMessages drops tool parts`; `applyEvent ignores unknown event types`.
- [ ] **Step 2: Run** → fail (module missing). **Step 3:** implement. **Step 4:** run → pass.
- [ ] **Step 5: Wire the service.** `OllamaService` exposes `property var draft` (the streaming `Msg`),
  `function resolveRequest(id: string, decision: string)` (writes the stdin line), keeps `send`, `cancel`
  (`chatProc.signal(15)`), `newChat`, sessions. On load, `messages = messages.map(Turn.migrateMessage)`.
- [ ] **Step 6: Verify live.** `qmllint shell/services/OllamaService.qml` clean; `bin/rice start`;
  `qs ipc call ollama send "what window is focused?"`; after it finishes `qs ipc call ollama lastMessage` names the
  focused window; `bin/rice logs` shows no new `TypeError`/`ReferenceError`.
- [ ] **Step 7: Commit** `feat(ai): parts reducer, service on the agent protocol`.

### Task 6: Message actions

**Files:** Modify `OllamaService.qml`, `components/ai/ChatMessage.qml`; Test: add to `turn.test.mjs`.

**Interfaces:** `turn.mjs` `truncateAt(msgs, index) -> Msg[]` (keeps `msgs[0..index)`). Service:
`regenerate(index)` (drop the assistant message at index and everything after, resend the previous user turn with
the current model), `editAndResend(index, text)` (user message at index replaced, later messages dropped),
`copyMessage(index)` (text parts joined → `wl-copy`). No branches (YAGNI; assistant-ui's BranchPicker is the
reference if wanted later).

- [ ] **Step 1:** tests `truncateAt keeps earlier turns only`, `truncateAt(0) empties`. **Step 2–4:** fail → implement → pass.
- [ ] **Step 5:** Actions row under each message, visible on hover or while focused: Copy (check icon 1.5 s, existing
  timer), Regenerate (assistant), Edit (user → the bubble becomes an inline editor, ⏎ resend, Esc cancel). Icon
  buttons 28 px hit area, press 0.97.
- [ ] **Step 6:** live check: edit the first message of a 3-turn chat → only 2 messages remain then a new answer
  streams. **Step 7: Commit** `feat(ai): copy, regenerate, edit`.

---

## Phase 3 — The interface

### Task 7: Timeline renders parts

**Files:** Modify `modules/assistant/AssistantOverlay.qml` (message Repeater → `ListView`), `components/ai/ChatMessage.qml`
(render `parts` in order), `components/ai/Tool.qml`, `components/ai/ReasoningBlock.qml`; Create
`components/ai/ToolGroup.qml`, `components/ai/ScrollToBottom.qml`.

**Decisions:**
- Parts render in order: reasoning → `ReasoningBlock`; consecutive tool parts → one `ToolGroup` ("Used 3 tools",
  collapsed when the turn is done, open while running; T3 `TimelineAssistantRows.tsx` work-log idea); text → the
  existing rendered text (`rice-render`).
- `Tool.qml` reads a Part: icon by `itemType` (command_execution `terminal`, web_search `globe`, image_view `image`,
  dynamic_tool_call `wrench`), title, mono input, output collapsed after 6 lines with "Show all".
- `ListView` with `cacheBuffer` 2 screens; sticks to bottom while the user hasn't scrolled up (prompt-kit
  chat-container); `ScrollToBottom` pill appears when > 1 screen from the bottom, fades in `enterMs`, out `exitMs`.
- New messages only (not ones restored on open): opacity 0→1 and y +6→0 over `Theme.enterMs`, `easeOut`;
  reduce motion: opacity only.
- Remove the dead streaming cursor in `ChatMessage.qml:195-208`; the reasoning shimmer stays the "thinking" cue.

- [ ] **Step 1:** implement. **Step 2:** `qmllint` on the changed files clean. **Step 3:** live: ask "search the web
  for Hyprland 0.57 release notes and summarise" → a web_search tool row runs, then text; scroll up mid-stream → view
  stays put and the pill shows; click it → glides to bottom. Screenshot with `grim -g "$(slurp)"` attached to the PR.
- [ ] **Step 4: Commit** `feat(ai): timeline of parts, tool groups, scroll pill`.

### Task 8: Approval card

**Files:** Create `components/ai/ApprovalCard.qml`; Modify `components/ai/ChatMessage.qml`,
`modules/assistant/AssistantOverlay.qml` (keys and the close path).

**Decisions:** Inside the tool row whose `request.state == "pending"`: summary line, `detail` in mono (the exact
command), buttons "Run" (accent) and "Don't run". Keys: ⌃⏎ run, Esc = don't run (Esc does not close the overlay while a
request is pending). Hiding the overlay or pressing Stop calls `OllamaService.cancel()` → the helper declines
(Task 3). After resolution the card collapses into the row's status (Ran / Declined / Timed out). Arrives with the
row (no separate entrance). References: AI Elements `confirmation.tsx`, T3 `TimelinePendingApprovalRow.tsx`, Codex
`approval_overlay.rs`.

- [ ] **Step 1:** implement. **Step 2:** qmllint. **Step 3:** live: "create a file ~/approval-test.txt" → card shows
  the exact command; "Don't run" → file absent, row reads Declined; repeat, ⌃⏎ → file exists. Open a request, hide
  the overlay → `bin/rice logs` shows the turn interrupted, file absent.
- [ ] **Step 4: Commit** `feat(ai): approval card`.

### Task 9: Model picker

**Files:** Modify `components/ai/ModelPickerMenu.qml`, `components/ai/PromptInput.qml` (pill opens it; Ctrl+K opens
it), `modules/assistant/AssistantOverlay.qml` (mount it; Ctrl+K handler), `services/OllamaService.qml`
(`property var modelInfo: ({})` — `{[name]: {capabilities: string[], sizeGb: number}}` filled from `/api/show` +
`/api/tags` in `probe()`), `bin/rice-ollama` `cmd_status` (include capabilities).

**Decisions:**
- A popover anchored above the pill, not a centred modal. Opens on `Spring { tier: Theme.springModerate }`: scale
  0.97 → 1 from the pill's corner (`transformOrigin` bottom-left), opacity `min(1, t*4)`, content 40 ms behind
  (`ActionMenu.qml` pattern). Close: tween `springModerate.exitMs` (120 ms) to scale 0.99 and opacity 0. Reduce
  motion: opacity only.
- Rows: name, size ("4.7 GB"), capability chips from real capabilities (Tools, Thinking, Vision); the running model
  gets a small "loaded" dot (from `/api/ps`). Drop the hard-coded catalog descriptions and the "Select Language / AI
  Model" header; header is "Model" with the filter field.
- Keyboard: opens with focus in the filter; type to filter; ↑↓ move a `FluidHighlight`; ⏎ choose; Esc closes and
  returns focus to the prompt. Outside click closes.
- Choosing a model without `tools` shows one line under it: "No tools with this model".
- References: T3 `ModelPickerContent.tsx` / `ModelListRow.tsx`, AI Elements `model-selector.tsx`.

- [ ] **Step 1:** implement. **Step 2:** qmllint. **Step 3:** live: click pill → opens from the pill; type "her" → one
  row; ⏎ → pill reads Hermes 3; Ctrl+K reopens; Esc closes and the prompt has focus; open+close fast 5× → no stuck
  half-open state (spring retargets).
- [ ] **Step 4: Commit** `feat(ai): model picker popover`.

### Task 10: App launcher motion

**Files:** Modify `modules/assistant/AssistantOverlay.qml:723-` (`appModal`).

**Decisions:** Keep the item alive while `t.value > 0.002 || open` (`Spring { tier: Theme.springSlow }`). Card
scale 0.96 → 1 + fade; backdrop opacity `0 → 0.65` over `enterMs`, out `exitMs`; close tween `springSlow.exitMs`
(160 ms). Reduce motion: fades only.

- [ ] **Step 1:** implement. **Step 2:** qmllint; live: Ctrl+O open/close, Esc mid-open turns around without a jump.
- [ ] **Step 3: Commit** `polish(ai): app launcher open/close`.

### Task 11: Motion polish (from the transitions review)

**Files and exact changes:**
- `components/ai/ChatSidebar.qml:28` close easing `Theme.easeInOut` → `Theme.easeOut`; `:37-38` add
  `easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut`; `:24` `enabled: !Theme.reduceMotion`.
- `components/ai/ModelPickerMenu.qml:151` `120` → `Theme.colorMs`.
- `components/ai/PromptInput.qml:394` `0.94` → `0.97`; `:396` → `Theme.pressMs` + `easeOut`; `:60-69` attachment
  height/opacity: `duration: OllamaService.pendingImage !== "" ? Theme.enterMs : Theme.exitMs`, `easeOut`.
- `components/ai/Tool.qml:169` and `:198` → `Theme.enterMs`, both ways.
- `components/ai/ReasoningBlock.qml:115` and `:145` → `Theme.enterMs`, both ways.
- `components/ai/ToolBadge.qml:44` `2000` → `1200` (match `Tool.qml:138`).

- [ ] **Step 1:** apply. **Step 2:** `grep -nE "duration: [0-9]" shell/components/ai/*.qml` lists only the three
  loops (Tool 1200, ToolBadge 1200, ReasoningBlock shimmer 1400 and pulse 600). **Step 3:** qmllint clean.
- [ ] **Step 4: Commit** `polish(ai): motion on Theme tokens`.

### Task 12: Composer — context chips and slash menu

**Files:** Modify `components/ai/PromptInput.qml`, `services/OllamaService.qml`; Create
`components/ai/ContextChip.qml`, `components/ai/SlashMenu.qml`.

**Decisions:**
- Pending context becomes a list of chips above the input: Window (app icon + title, thumbnail), Screenshot,
  Selection (first line), Clipboard (first line). Each removable (× or ⌫ on an empty input removes the last). They
  map to `messages[-1].context` and `image` (Task 4). Chips enter with opacity + 4 px over `enterMs`, leave in
  `exitMs`; the row reflows on `reflowMs`.
- Snapshot no longer switches the model to minicpm (the helper's vision hop handles it) — delete that block in
  `snapWinProc.onExited`.
- `/` at the start of an empty input opens `SlashMenu` (same popover motion as Task 9): `/new`, `/clear`, `/snap`,
  `/open <app>`, `/model`. Filter as you type, ⏎ runs. Reference T3 `ComposerCommandMenu.tsx`.
- `ContextMeter` shows `stats.promptEvalCount / stats.numCtx` from the last `turn.completed`.

- [ ] **Step 1:** implement. **Step 2:** qmllint. **Step 3:** live: select text in a terminal, Super+Ctrl+Shift+A,
  /snap → Window + Selection chips; remove Selection; ask "what am I looking at?" with hermes → an image_view row,
  then an answer naming the app; meter moves.
- [ ] **Step 4: Commit** `feat(ai): context chips, slash menu, real context meter`.

### Task 13: Docs

**Files:** `docs/CHAT.md` (status: local agent built, protocol section pointing at this plan; the Codex/Claude
backends emit the same events), `docs/REQUESTS.md` (tick the chat item as partly done), `README.md` (assistant row
and keys: Ctrl+K model, Ctrl+O apps, ⌃⏎ run).

- [ ] **Step 1:** write. **Step 2: Commit** `docs: assistant agent`.

---

## Out of scope (named so nobody builds them by accident)

Conversation branches, voice input, MCP servers, Codex/Claude providers (docs/CHAT.md steps 1–2), artifacts/canvas,
file attachments other than images, multi-window sub-agents. The event protocol leaves room for each.
