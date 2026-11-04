# AI Elements → the rice assistant

Every component in shadcn's AI Elements (`refs/vercel_ai-elements/packages/elements/src/`, grouped as in
its docs), what it's for, where chat apps use it, and where it stands here. Status as of 2026-11-03.

**Built** = ours does the job · **Partial** = some of it · **Next** = worth doing · **Skip** = doesn't fit a
local single-user desktop assistant (reason given).

## Chatbot

| Component | What it's for / where it's used | Here | Ours |
|---|---|---|---|
| Conversation | message list that sticks to the bottom, scroll-to-bottom button, empty state, download | Built | overlay `scroll` + jump button, empty state, `/` Copy chat as Markdown |
| Message | a turn: content, actions (copy, retry, edit), branches | Built (no branches) | `ChatMessage.qml`, `MessageAction.qml` |
| Prompt Input | the composer: textarea, attachments, model, submit/stop | Built | `PromptInput.qml` (chips, `/`, steer ↵ / queue ⇥, send↔stop) |
| Model Selector | searchable model command palette | Built | `ModelPickerMenu.qml` (real capabilities, Kobra ranking) |
| Queue | messages waiting while the agent works; todo lists | Built | queue list in the composer, `OllamaService.queue` / `steering` |
| Reasoning | thinking that opens while streaming and folds after | Built | `ReasoningBlock.qml` (sweep, auto-fold 1 s, "Thought for Ns") |
| Chain of Thought | reasoning steps with search results and progress | Built (as rows) | reasoning + tool rows in order, `ToolGroup.qml` |
| Tool | one tool call: input, output, state | Built | `Tool.qml` (durations, Show all, Copy) |
| Confirmation | approve / reject a tool before it runs | Built | `ApprovalCard.qml` (⌃↵ / Esc, declines on close, 120 s timeout) |
| Task | collapsible list of steps with status | Built (as groups) | `ToolGroup.qml` ("Used N tools") |
| Sources | the citations an answer used | Built | Sources chips (`Turn.sourcesOf`: pages read, then results) |
| Inline Citation | hover cards on [n] inside the text | Skip | small local models don't cite reliably (measured mis-copied dates); chips instead |
| Suggestion | clickable prompt chips | Built | `Suggestion.qml` in the empty state |
| Shimmer | text shimmer for loading | Built | reasoning sweep (`MultiEffect` mask) |
| Context | context-window usage, tokens, cost | Built | `ContextMeter.qml` ring by Send; hover: tokens, compaction note (no cost: local) |
| Attachments | files, images, sources on a message | Built | screenshot / window / selection / clipboard chips, files (paperclip, drop; text and PDF inline, copied into the sandbox) |
| Checkpoint | mark a point and restore the chat to it | Partial | Edit resends from a message, Retry reruns an answer (both cut later turns) |
| Plan | an agent's plan before it acts | Built | `update_plan` tool → `PlanCard.qml`, one checklist updated in place (n of m) |
| Question | the agent asks you to pick an option / type | Built | `ask_user` → `QuestionCard.qml`: 1–9 picks, type your own, Esc skips |

## Code

| Component | What it's for | Here | Ours |
|---|---|---|---|
| Code Block | highlighted code, language, copy | Built | answer split by `Turn.splitFences`; block with language + Copy, live while streaming, rice-render highlight when done |
| Terminal | streaming console output, exit status | Built | command rows (`$ cmd`, output), red exit-code chip, ANSI stripped, Sandbox tag |
| Snippet | inline command with copy | Partial | code blocks; inline code renders as Markdown |
| Stack Trace, Test Results, Commit, File Tree, Package Info, Environment Variables, Schema Display, Sandbox, JSX Preview, Web Preview, Artifact, Agent | coding-agent and generated-UI views | Skip | this is a desktop helper, not a coding agent (Codex / Claude Code / T3 Code do that) |

## Voice

| Component | Here | Why |
|---|---|---|
| Speech Input, Transcription, Mic Selector | Built (speech input) | mic button / ⌃D hands off to voxtype, text lands at the cursor |
| Audio Player, Voice Selector, Persona | Skip | no text-to-speech model locally |

## Utilities and Workflow

Shimmer (`components/Shimmer.qml`: loading, thinking) and scroll-fade (the chat's edges) are built.
File Tree: built flat, as file chips under an answer for what it wrote in the sandbox, plus the folder.


| Component | Here | Why |
|---|---|---|
| Image | Built | screenshots in your bubble, thumbnails in chips |
| Open in Chat | Skip | the subscription providers come through their own backends later (docs/CHAT.md) |
| Canvas, Node, Edge, Connection, Controls, Panel, Toolbar | Skip | React Flow workflow builders |

## Queue and steer (how it works)

Codex's model (`refs/openai_codex/codex-rs/tui/src/chatwidget/input_flow.rs`, `input_queue.rs`):

- While an answer streams, **↵ steers**: the message goes into the running turn. The agent
  (`bin/rice_agent.py`, `turn.steer` on stdin) cuts the text being written (the partial stays), adds your
  message and the model answers it in the same turn; during a tool or an approval it lands right after.
  It shows as your bubble inside the turn (`turn.steered` → a `steer` part).
- **⇥ queues** it for after this answer (with its screenshot and context). Queued messages send one by
  one when a turn finishes normally, not after Stop or a failure. Hover a queued one: send now, edit, remove.
- A steer the turn couldn't take (it arrived as the turn ended, or carried an attachment) goes to the
  front of the queue (`turn.completed.unapplied`).
- History sends a steered turn back as it happened: assistant, your steer, assistant (`Turn.toApiMessagesWithIndex`).
