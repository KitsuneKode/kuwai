# Island

The island is kuwai's top-edge status surface. At rest it shows workspaces, the clock, status, and any active live item (timer, recording, dictation, or media). Hovering reveals a glance row; clicking or pulling down grows the full panel.

## Bar modes and rest styles

- Switch between **Island** (default) and **Waybar**: `Settings → Bar & Island`, or `kuwai bar island|waybar`.
- Toggle rest density (`minimal` vs `full`): `Ctrl+Alt+Shift+W`.
- Tuck or untuck the island: `Ctrl+Alt+W`.
- Peek details while in minimal mode: `Super+Alt+I`.
- Try every island state without real agents: `kuwai demo` (`--fast`, `--step`, or `--screen NAME`).

## Capsules and sections

Background activity floats beside the notch in separate capsules (Settings → Bar & Island → *Separate pills*):

- **Agents** (working count) and **Approval** (orange capsule when an agent waits for permission or an answer).
- **Usage limits** (orange ring with the soonest reset time when an account hits a cap).
- **System news** (updates available, high CPU/temperature/memory warning, or idle projects when `sweep` is installed).
- **Minimised windows** (`Super+O`).

**Agents, Usage, System, and Cleanup** share one header strip inside the island. Switch between them by clicking the strip or pressing **`Alt+1`** through **`Alt+4`**.

- **Agents (`Super+Shift+N`, `Alt+1`)**: Lists kitty/kittymux panes, T3 Code threads, and desktop agents reporting through `bin/kuwai-agent-hook`, waiting items first. `Super+Ctrl+A` jumps straight to the waiting agent. Native `PermissionRequest` hooks (Claude Code/Codex via kittymux) and T3 operate tokens let you click Allow or Deny without typing keystrokes into a pane.
- **Usage (`kuwai usage`, `Alt+2`)**: Per-account limit bars and reset countdowns plus local token spend (`bin/kuwai-spend`).
- **System (`kuwai system`, `Alt+3`)**: CPU, proportional memory by app (browsers counted once), GPU state, and quick mode toggles.
- **Cleanup (`Alt+4`)**: Unused agent skills (30/90/180 days) with token counts and Trash + **Put back**, recoverable tool caches (`bin/kuwai-storage`; Docker and the systemd journal are listed "check first" with the commands that shrink them: only `docker image prune` and `docker builder prune` can be run from the panel, after a second click; volumes, stopped containers and the system journal are commands to copy), and idle project builds when `sweep` is installed (`bin/kuwai-sweep`).

Custom capsules can also be published from scripts with `kuwai capsule set NAME --text "…"`.

## Usage limits in the notch

`bin/kuwai-usage --watch` reads usage data from T3 Code (over localhost using a read-only token), local Devin CLI profiles, or kittymux's `agent-usage.json` fallback.

- **Approaching** (window ≥ 80%, configurable in `Settings → Island Behaviour`): shows one moment once per window per reset period, remembered in `~/.local/state/kuwai/limits-told.json`.
- **Used up** (100%): shows a moment and keeps an orange ring with the soonest reset time beside the notch until the window resets.
- **Setting up T3 Code tokens (optional):**

```sh
umask 077; mkdir -p ~/.local/state/kuwai
t3 auth session issue --scope orchestration:read --scope diagnostics:read --label kuwai-usage --ttl 365d --token-only > ~/.local/state/kuwai/t3-token
```

To answer T3 permission requests from the notch, issue a separate operate token (`~/.local/state/kuwai/t3-operate-token` at mode `0600`, or store it in the system keyring with `secret-tool store --label kuwai service kuwai key t3-operate-token`).

## Media and Now Playing

- While media plays, the rest row shows album art and live levels (if enabled in `Settings → Bar & Island`). Paused tracks show art and a still silhouette beside the clock.
- Click the media card or hover to open **Now Playing** with a seek bar and transport controls (`Space` play/pause, `←`/`→` ±10 s, `Shift+←`/`→` ±30 s, `N`/`P` next/prev, `S` shuffle, `R` repeat).
- `bin/kuwai-player` provides one player-specific action (`L`): Cider love rating (via Cider's local API, token in keyring via `kuwai-player cider-token`) or copying the current timestamped URL from supported browsers.

## Privacy dots and cards

- **Privacy dots** beside status show active microphone (orange), camera (green), and screen share/recording (purple), naming the process on hover.
- **Cards** for ringing alarms, due reminders, finished timers, and connecting audio devices grow out of the notch. Answer them from the keyboard with `Super+Ctrl+Enter`.
- **Settings**: open with `Super+Ctrl+I`, from the launcher, or `kuwai settings`.
