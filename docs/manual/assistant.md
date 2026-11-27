# Assistant (opt-in)

kuwai includes an optional local assistant overlay (**`Super+Ctrl+Shift+A`** or `kuwai assistant [here|open]`) backed by a local **Ollama** server (`shell/modules/assistant/`, `bin/kuwai_agent.py`).

## Opt-in (off by default)

Enable it in **`Settings → Assistant`**. Until enabled, pressing `Super+Ctrl+Shift+A` opens `Settings → Assistant` and Ollama is not contacted.

## What it does

- Runs chat and tool-calling sessions against models available on your local Ollama instance (`Ctrl+K` switches models).
- Optional context tools can inspect the focused window, system load, clipboard, selection, files under your home directory, and optional web search.
- Before running a shell command, opening an application, or opening a URL, the assistant asks for explicit confirmation (`Ctrl+Enter` to run, `Esc` to decline).
- Screenshots attached with `Ctrl+V` route through a vision-capable model first when your selected chat model is text-only.

## Privacy and safety boundaries

- Secret-shaped text is redacted from clipboard/selection reads and sandbox logs (`bin/kuwai_redact.py`).
- File reads and searches follow the same secret-exclusion policy (`tests/agent/test_file_policy.py`), and sandboxed files are opened without following symlinks (`tests/agent/test_sandbox_boundary.py`).
- Chat mode does not read the clipboard or run system audits automatically, and terminal last-command context is off unless enabled.
- Streaming Markdown strips inline remote image fetches (`Turn.liveMarkdown`), and opened links are restricted to web and mail schemes (`Links.safeLink`).

## Crash diagnosis

When `coredumpctl` records a new user coredump (`bin/kuwai-crash-poll`), kuwai posts a warning notification with **Diagnose** and **Dismiss**. Choosing **Diagnose** opens the assistant with a local crash summary ready for you to review and send (requires Assistant opt-in).

## Keys inside the assistant

`Enter` send · `Shift+Enter` newline · `Ctrl+K` switch model · `/` commands · `Ctrl+V` paste image · `Ctrl+N` new chat · `Ctrl+O` apps · `Ctrl+B` sidebar · `Ctrl+Enter` approve pending action · `Esc` decline, stop generation, then close.
