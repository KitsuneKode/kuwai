# Assistant

## Opt-in (default off)

Turn on in **Settings → Assistant**, or accept the prompt when you press **Super+Ctrl+Shift+A** the first time.

Until opt-in: overlay shows **Turn on / Not now** only; Ollama is not started for chat.

## Crash diagnose

When `coredumpctl` sees a new user coredump, rice shows a **warning toast** with **Diagnose** / **Dismiss**.

**Diagnose** opens the assistant and enqueues a crash brief (local only; you edit/send). Requires assistant opt-in.

## Agent CLIs (lazy stubs)

Optional stubs in `bin/agents/` — first run prints install hint; wire your preferred agent (claude, codex, …) like Omarchy’s mise pattern.

## Usage limits

Center **Agents** tab and island chip read `bin/rice-usage` (T3 Code token or kittymux fallback). See README for `t3 auth session issue`.
