# Agent backend: web search, compaction, small-model tool habits

2026-11-03. Done in the main session after three delegated attempts failed on quota (Codex, Antigravity,
Claude-2). Everything marked **measured** was run on this machine (RTX 4050 6 GB, Ollama 0.40.13) with
the harnesses described below; the rest is cited.

## A. Free web search

- **DuckDuckGo HTML** (`POST https://html.duckduckgo.com/html/`, form `q=…`, a browser User-Agent):
  **measured** 10 results for "hyprland 0.57 release notes", each `a.result__a` (title, href; some
  hrefs are `//duckduckgo.com/l/?uddg=<url>` redirects) and `a.result__snippet`. No key, no daemon.
  This is the default.
- **SearXNG** (self-hosted): `GET {base}/search?q=…&format=json` → `results[].{title,url,content}`;
  JSON must be enabled under `search.formats` in `settings.yml`, or it answers HTML / 403.
  [litellm docs](https://docs.litellm.ai/docs/search/searxng.md),
  [Open WebUI docs](https://docs.openwebui.com/features/web-search/searxng). Used first when
  `RICE_SEARXNG_URL` is set.
- **Ollama web search**: `POST https://ollama.com/api/web_search` with `Authorization: Bearer
  $OLLAMA_API_KEY`, `{query, max_results}`; free with an ollama.com account, limits not published
  ([AlternativeTo](https://alternativeto.net/news/2025/9/ollama-launches-web-search-api-to-boost-ai-model-accuracy-and-reduce-hallucinations),
  [Apidog](https://apidog.com/blog/ollama-web-search-api-mcp-server)). Used second when the key is set.
- The DuckDuckGo instant-answer API (`api.duckduckgo.com`) that was there before returns nothing for
  most real queries: dropped.
- **web_fetch**: stdlib `html.parser`, drop script/style/nav/header/footer/aside/form, blocks to lines,
  title first, 8,000 characters (~2k tokens). **Measured** on hypr.land/news/update57: 1,959 clean
  characters. Sniff `<!doctype html` too: that server sends no HTML content type.

Built: `bin/rice_agent.py` `tool_web_search` (chain SearXNG → Ollama → DuckDuckGo) and `tool_web_fetch`.

## B. Compaction

- Codex compacts when tokens pass `model_auto_compact_token_limit` (capped at 90% of the window since
  v0.100), with a handoff prompt (`codex-rs/core/templates/compact/prompt.md`: a summary "for another
  LLM that will resume the task"), rebuilding history from the summary plus recent user messages
  ([gist](https://gist.github.com/badlogic/cd2ef65b0697c4dbe2d13fbecb0a0a5f),
  [Vaughan](https://codex.danielvaughan.com/2026/04/14/context-compaction-deep-dive-codex-cli-claude-code-opencode/);
  the TUI shows "N% context left", `refs/openai_codex/codex-rs/tui/src/bottom_pane/footer.rs`).
- Ours, for a 4,096 window: compact before a turn when the last turn used ≥ 75% of the window or the
  history estimate (characters / 4 + ~900 for system prompt and tools) is ≥ 75%; keep the last two
  exchanges verbatim; the loaded model writes ≤ 200 words of bullets (prompt: `COMPACT_PROMPT`),
  folding in the previous summary; each message cut to 1,500 characters in the summary input so one
  runaway can't crowd out the rest. The chat keeps `summary` + `summaryUpTo`; later turns send
  summary + messages since. The row reads "Summarising earlier messages" and opens to the note.
- **Measured**: the summary must go in as an opening user/assistant exchange. As a second system
  message, hermes3 with tools offered ignored it *and every message after it*: recall 0/5 → 5/5 (3/3
  runs) once moved. Without tools it was 5/5 either way.
- num_ctx stays 4096: an 8B Q4 model is 4.7–5.2 GB of the 6 GB, the rest is KV cache and the desktop.

## C. Small models and tools

**Measured** (5 prompts × 3 runs, approvals auto-declined, `tests/agent/live/toolhabits.py`):

| | hermes3:8b before | hermes3:8b after | deepseek-r1:8b after |
|---|---|---|---|
| "Run the shell command: touch …" calls run_command | 0/3 (asks "type yes") | 3/3 | 0/1 |
| "Open Firefox" calls launch_app | 3/3 | 3/3 | 0/1 |
| "What app am I using" calls active_window | 3/3 | 3/3 | 0/1 |
| Plain question answered without a tool | 0/3 (web search) | 0/3 (web search) | 1/1, 14.5 s (was 90 s+) |

- What fixed hermes: say outright that the app shows its own Run / Don't run prompt and never to ask
  in text, and drop "the user approves it first" from tool descriptions (small models read it as
  "ask first"). Searching the web for plain facts costs 2.5–5 s and avoids made-up answers: kept.
- deepseek-r1:8b (Ollama lists it as tools + thinking) doesn't actually call tools; treat it as the
  thinking model, hermes3 as the tool model.
- Ollama's `num_predict` is unlimited by default; hermes3 looped one sentence for 48,000 characters.
  Now capped at 2048 tokens, and a round stops when its last 200 characters already appear 5 times.
- Next model to try for tools + thinking in 6 GB: Qwen3 4B / Qwen3.5 4B (2.5–3.4 GB, leaves room for
  context); Qwen3 8B is tight at Q4 ([LocalAIMaster](https://localaimaster.com/vram/best-ollama-models-6gb-vram),
  [PromptQuorum](https://www.promptquorum.com/es/power-local-llm/best-local-models-tool-calling-2026)).
  No independent function-calling benchmark covers them; run `tests/agent/live/toolhabits.py current <model> 3` and `recall.py` on one before switching.

## D. Not built yet (from the ChatGPT / Claude desktop apps)

Memory across chats, projects, voice input, file attachments other than images, MCP servers,
conversation branches, the subscription backends (docs/CHAT.md). The event protocol has room for each.
