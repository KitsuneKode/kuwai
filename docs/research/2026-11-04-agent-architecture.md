# Agent architecture: what we borrowed from pi and Codex

2026-11-04. Studied `refs/badlogic_pi-mono` (pi coding agent) and `refs/openai_codex/codex-rs`; adapted for
a 4B model with a 16k window (8k for the 8B) running in `bin/rice_agent.py`.

## Tools (20, ~2,500 prompt tokens with the system prompt, measured on qwen3.5:4b)

| Group | Tools | From |
|---|---|---|
| Files | `read` (250 lines / 12 KB, "Use offset=N to continue"), `write`, `edit` (exact oldText → newText, several per call, matched against the original, fuzzy fallback on trailing spaces / smart quotes), `ls`, `find` (fd), `grep` (rg) | pi `coding-agent/src/core/tools` |
| Sandbox | `sandbox_run` (Docker, no approval) | ours |
| Your machine | `run_command`, `launch_app`, `open_url` (ask first) | ours |
| Web | `web_search`, `web_fetch` (JS pages via the sandbox's Chromium), `shop_search` | ours |
| Desktop | `active_window`, `system_info`, `read_clipboard`, `read_selection` | ours |
| Agent | `update_plan` (Codex `plan_spec.rs`), `ask_user`, `remember` | Codex / AI Elements / ChatGPT |

Paths: relative = the chat's sandbox folder (free); `~/…` or `/…` = your files: reading is free except
secrets (`~/.ssh`, `~/.gnupg`, keyrings, `.env`, `*.pem`, `id_*`…), writing or editing shows a Save prompt
with the diff (`ApprovalCard` kind `write`).

## Loop behaviour

- Missing required arguments come back as pi's `Validation failed for tool "x": missing … Received
  arguments: {…}` so the model fixes the call itself.
- A reply cut at the output limit (`done_reason: length`) never runs its tool calls; the model is told to
  call again with complete arguments (pi `agent-loop.ts`).
- Command output: Codex's head + tail (4 KB each, the middle cut with a count), ANSI stripped.
- Plan updates don't use up the 10 tool rounds; out of rounds, the last round answers with no tools and no
  thinking and says what's left; a turn that finishes tool work in silence gets one "answer now" nudge.
- Declined actions aren't retried.

## Context (`bin/rice_context.py`, in every system prompt)

- **About this computer**: OS, kernel, desktop, shell, terminal, browser, CPU/GPU/RAM, package managers,
  home folders and `~/Projects` (cached a day in `~/.cache/rice/assistant/system.md`, ~200 tokens).
- **Your instructions**: `~/.config/rice/assistant/AGENTS.md` (pi / Codex's AGENTS.md, one global file,
  capped at 4 KB).
- **Memory**: `~/.config/rice/assistant/memory.md`, appended by `remember` (capped at 3 KB; edit freely).
- **Skills**: `~/.config/rice/assistant/skills/<name>/SKILL.md` — only name + description + path go in the
  prompt; the model reads the file when a task matches (pi's progressive disclosure).

## Measured after the change (`partner.py`, 13 tasks, one run each)

| Model | Right tool | Right answer | Refused | Avg turn |
|---|---|---|---|---|
| qwen3.5:4b (16k) | 10/10 | 9/10 | 1/3 (lock picking, this run) | 15.0 s |
| huihui_ai/qwen3-abliterated:8b (8k) | 9/10 | 8/10 | 0/3 | 111.8 s (one 885 s sandbox loop) |

New tasks: find the file that draws the context ring in ~/Projects/rice (4B: found ContextMeter.qml via
ls → grep → read; 8B: named the wrong file), remember a fact (both used `remember`), write a buggy file in
the sandbox, run it, fix it with `edit`, run again (both: 5). Stock refusals vary run to run, which is why
the uncensored picks stay.

## Bigger models through RAM (2026-11-05)

Mixture-of-experts models run mostly from the 23 GB of RAM; models live on Depot (`OLLAMA_MODELS=~/Depot/ollama/models`).

| Model (8k) | Speed | Load | Right tool | Right answer | Refused | Avg turn | Notes |
|---|---|---|---|---|---|---|---|
| gpt-oss:20b | 16.8 tok/s | 27.6 s cold | 9/10 | 8/10 | 0/3 | 40 s | kept as **Deep**; searched the web instead of shop_search (guide now says to use it), looped on the repo task and called a tool that doesn't exist ("open") |
| qwen3:30b-a3b | 12.6 tok/s | 26.7 s cold | 9/10 | 7/10 | 1/3 | 80 s | dropped: empty code answer, named the wrong file, refused lock picking |

## Tool routing + 8-bit KV cache (2026-11-05)

`OLLAMA_KV_CACHE_TYPE=q8_0` (systemd override) puts qwen3.5:4b at 16k wholly in VRAM (3.36 GB): 200-token
generation 51.1 tok/s (was 27.5). With routing (each request offers only the tool groups its words point to),
the same 13 tasks: **10/10 right tool, 9/10 right answer, 0/3 refused, 7.7 s a turn** (was 15.0 s). The one miss:
the repo task found ContextMeter.qml but didn't state the ring size. The fix-it task tried `run_command` on the
host twice before using the sandbox ("run" also routes the host-action group).

## Three runs per task, and coding models (2026-11-05)

qwen3.5:4b, 15 tasks × 3 runs (router + q8 KV): right tool 34/36, right answer **27/36 (75%)**, refused 0/9,
13.4 s a turn. The weak spots were coding: two failures were real bugs — the model ran its files from
`~/sandbox` (the guide now says relative files live in sandbox_run's folder) and Ollama failed whole turns on
qwen3.5's broken tool-call XML (now sent back to the model to retry, as pi does). After both fixes, the coding
tasks × 3: fix-a-bug 3/3 (was 1/3), pytest-until-green 3/3 (was 1/3), code 2/3, repo 1/3.

| Coding model | Speed | Right answer (coding tasks) | Avg turn | Kept |
|---|---|---|---|---|
| qwen3.5:4b (16k) | ~50 tok/s | 9/12 | 31 s | yes, default |
| qwen3-coder:30b MoE (8k, RAM+VRAM) | ~22 tok/s | 6/10 (pytest 0/2, repo 0/2) | 52 s | no, deleted |

The bigger coders that score best in published rankings (Qwen3.8 27B, Devstral Small 2 24B) are dense and
would run mostly on the CPU here.

## Not taken (yet)

- pi's session tree / branches (we have linear chats with Edit and Retry).
- Codex's `apply_patch` grammar (harder for a 4B model to emit than JSON oldText/newText).
- Codex's long-running `exec_command` sessions with `write_stdin`.
