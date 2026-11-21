# ADR-006: Local AI Assistant Security Architecture, Per-Chat Container Jail, and Small-Model Prompting

## Status
Accepted

## Date
2026-11-21

## Context
kuwai's local AI assistant (`bin/kuwai_agent.py`, `bin/kuwai_sandbox.py`,
`bin/kuwai_files.py`, `bin/kuwai_context.py`, `bin/kuwai_md.py`,
`bin/kuwai-ollama`, `bin/kuwai-render`) runs small local models (4B–8B, 4k–16k
context) with tool access on a user's personal workstation. Red-team testing
and empirical benchmarks against real models (`hermes3`, `deepseek-r1`,
`qwen3.5:4b`) identified critical security and reliability requirements:

- A shared sandbox container allowed one chat to read another chat's files or
  plant executables on `$PATH` for later chats.
- Resolving a write path twice (once for approval, once for writing) allowed a
  container to swap a symlink in between and turn an approval-free sandbox
  write into a host write.
- A container could turn any path under `/work` into a symlink, FIFO, or hard
  link to trick host-side reads, or fill the host disk via unbounded job logs
  or stdout.
- Unbounded `num_predict` or repeated plan-only turns caused small models to
  loop indefinitely.
- With tools offered, `hermes3` ignored everything after a second `system`
  message (0/5 recall vs 5/5 with an opening user/assistant exchange), and tool
  descriptions mentioning "the user approves it" caused small models to ask
  "type yes" in text instead of invoking tools (0/3 vs 3/3).
- Python 3.14 broke `python-markdown`, leaving every chat block rendered as raw
  text.

## Decision

1. **Per-chat container isolation and symlink-proof host I/O (`bin/kuwai_sandbox.py`, `bin/kuwai_files.py`, `bin/kuwai-ollama`)**:
   - Run one Docker container per chat mounting only its own folder at
     `/work/<chat>` with `$HOME` inside it, connected to a dedicated
     `kuwai-jail` Docker network so `DOCKER-USER` firewall rules block egress
     to private/LAN subnets (even when Chromium follows redirects). Stop idle
     containers after 30 minutes when no background job is active.
   - Strip leading dots from chat IDs so `..`, `.`, and `.home` can never
     escape `/work`.
   - Host-side access to container-writable files walks directory descriptors
     one component at a time (`O_NOFOLLOW`), refusing symlinks, FIFOs, and
     hard links at every step.
   - Cap background jobs by duration (`JOB_HOURS`) and log size (`head -c` at
     20 MB while preserving exit status via `set -o pipefail`).
   - Bound all host process output via `kuwai_files.run_bounded` (~64 KB head +
     tail) so gigabyte-producing commands never exhaust host RAM.
   - Pass `--` before user/model patterns in `fd` (preventing `--exec` /
     `--follow` flag injection) and `--null` in `rg` so every path is checked
     against the secrets denylist (`~/.ssh`, `~/.gnupg`, keyrings,
     `.password-store`, `id_*`, `*.pem`, `*.key`, `.env*`, `credentials*`,
     `*.kdbx`), applied equally to `read`, `grep`, and file attachments.

2. **Execution-time approval binding and Chat-mode enforcement (`bin/kuwai_agent.py`)**:
   - Decide write targets ONCE from the path as written (without following
     links) into `_DECIDED` for the duration of a single tool call so approval
     and execution act on the exact same decision, then clear `_DECIDED`.
   - Include `cwd` in command approval prompts (`cat id_ed25519` inside
     `~/.ssh` must be visible to the approver).
   - Enforce Chat-mode read-only restrictions at tool execution time
     (`MODE == "chat" and name not in CHAT_SAFE`), not solely by omitting
     schemas, and exclude `remember` from Chat mode so fetched web pages cannot
     plant persistent instructions.

3. **Small-model prompting, routing, compaction, and loop guards (`bin/kuwai_agent.py`, `bin/kuwai_context.py`)**:
   - Cap generation at `NUM_PREDICT = 2048` tokens, break stuck re-planning
     loops at `plan_streak >= 4` (while not charging real plan updates against
     the work round limit), skip execution on length-truncated tool calls, and
     issue a single nudge when a thinking model stops without a final message
     after tool work.
   - Route tool groups dynamically based on recent user intent (avoiding ~2,500
     tokens of unused schemas) and keep host-action tools gated behind explicit
     host triggers; filter shared `~/.agents/skills` (150+ skills ≈ 11k tokens)
     to only query-relevant skills.
   - Inject compaction summaries as an opening `user`/`assistant` exchange
     rather than a second `system` message (5/5 vs 0/5 recall on `hermes3`),
     keep ~30% of context for recent exchanges, and cap attached files at ~40%
     of `num_ctx`.
   - Phrase `TOOL_GUIDE` without telling the model "the user approves it" so
     small models emit tool calls directly (measured 3/3 on `hermes3`, ~15 s vs
     90+ s reasoning on `deepseek-r1`).

4. **Stdlib streaming Markdown renderer (`bin/kuwai_md.py`, `bin/kuwai-render`)**:
   - Use an internal stdlib Streamdown-style renderer (`kuwai_md.py`) with
     open-block healing during streaming, `-qt-list-indent` for Qt nested
     lists, and strict `http`/`https`/`mailto` link allowlisting (showing other
     schemes as plain text). Catch per-block render errors so the chat falls
     back to Qt Markdown instead of crashing the render server.

## Alternatives Considered

- **Single shared sandbox container across chats**:
  Rejected after red-team testing demonstrated cross-chat file and `$PATH`
  contamination.
- **Relying on schema omission alone to enforce Chat mode**:
  Rejected because models can emit tool calls for unlisted schemas.
- **Depending on `python-markdown`**:
  Rejected after Python 3.14 upgrades broke the package and degraded rendering.

## Consequences
- Every chat incurs a lightweight per-chat container lifecycle, bounded by the
  30-minute idle reaper.
- Prompting and compaction conventions are tuned for small local Ollama models
  and verified by `tests/agent/`.
