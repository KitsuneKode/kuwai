# Chat: a native ask-anything window for the rice

Status: planned (2026-10-29). Nothing built yet.

## Why

Quick questions and research currently mean opening a browser tab (ChatGPT, Gemini) and waiting for it, or starting
a Codex or Claude CLI session, which fills the coding history with throwaway chats. This is a third place: a native
window that answers through the subscriptions you already pay for, keeps its own history, and is there the moment you
press its key.

## Shape

- **UI: Quickshell, the rice's own primitives**, not a webview. A floating glass window (GlassCard, Elevation, the
  island's motion vocabulary): a sidebar of chats with search, the conversation, a prompt bar with attachments.
  Messages render with the clipboard's renderer (`bin/rice-render`: Markdown, highlighted code, Mermaid). Reasoning
  folds away; sources show as citation chips and a list (the ideas of AI Elements' Reasoning, Sources, Inline
  Citation and Message, drawn in QML).
- **Backend: a local Bun process** (`chat/`), started on first use and kept warm while the window is in use, idle-
  exits after a while. The window talks to it over a Unix socket (JSON lines): send, stream, stop, list, search.
- **Providers, through their official harnesses** (the way T3 Code does it, so the subscription is used as intended):
  - Codex: `codex app-server` (JSON-RPC over stdio), signed in with ChatGPT. Read-only sandbox, no approvals for
    anything that writes; web search on.
  - Claude: the Claude Agent SDK (`@anthropic-ai/claude-agent-sdk`), signed in with your Claude login. Tools limited to
    web search and fetch; no shell, no file writes.
  - Gemini (later): the Gemini CLI in its non-interactive JSON mode.
- **History**: its own SQLite file in `~/.local/share/rice/chat/` (chats, messages, attachments), searchable (FTS5).
  Nothing goes into the Codex or Claude CLI histories beyond what their harnesses keep for the session itself.
- **Attachments**: images (paste from the clipboard island, drop, or pick) and files (PDFs, text) go to the provider
  the way its harness accepts them.

## Staying within the rules

- Use only the providers' own CLIs and SDKs with your own sign-in, on your own machine, for your own questions. No
  scraping the web apps, no shared accounts, no reselling, no automation that runs unattended in a loop.
- Read-only tools: a chat never edits files or runs commands.
- Show remaining usage (the Agents tab's numbers) in the window, so heavy research doesn't eat the coding budget.

## GPU

The UI renders on the GPU through Qt like the rest of the rice. The models run at OpenAI and Anthropic, so the chat
itself needs no local GPU. Optional later: a small local model (loaded on demand, unloaded when idle, VRAM shared
with voxtype) for instant offline answers, semantic search over chat history, and image captions.

## Steps

1. Bun backend: Codex via app-server, one streamed chat, stored in SQLite. A CLI check (`rice-chat ask "…"`).
2. Claude via the Agent SDK, same protocol.
3. The window: sidebar, conversation, prompt bar, streaming, stop, rendered Markdown/code.
4. Attachments (images first), sources and citations, reasoning folds.
5. Search across chats; a shortcut sheet; Gemini.
