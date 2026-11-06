# Security notes (kuwai / rice shell)

Last reviewed: 2026-11-05.

## Fixed / hardened in this track

| Area | Mitigation |
|------|------------|
| **rice-notify** | `-H` keys restricted to `x-rice-*`; values JSON-escaped via `jq`; argv for title/body/app |
| **Usage limit moments** | Read-only `rice-usage`; labels shown as text in the island, no notifications sent |
| **Crash alerts** | Brief truncated; uses rice-notify + adapter gate for diagnose action |
| **Root updater** | Fuzzed in `tests/root` (no shell interpolation in helper) |

## Known gaps (Phase 6 — do before assistant default-on)

| Risk | Status | Mitigation planned |
|------|--------|-------------------|
| **Assistant tool exec** | Ollama sandbox exists; not fully audited | Deny-list `sudo`, `rm -rf`, `curl \| sh`; confirm dangerous commands |
| **Idle.qml `sh -c`** | Fixed commands only | Keep audit when adding idle hooks |
| **Launcher xdg-open** | User-driven search | URLs encoded; no auto-exec of pasted shell |
| **notify-send fallback** | kuwai session restore only | Prefer rice-notify |

## Flaky behaviour to watch

| Symptom | Cause | Fix |
|---------|-------|-----|
| Welcome back pill empty on the right | `away` was blank for short unlocks; moment split label/value across island sides | Fixed: unified hello row + “Unlocked” when <1 min |
| Notch stuck after fast unlock | Welcome moment queued behind another; island width min 220 | Hello cuts in; +520 ms delay after unlock anim |
| Volume HUD looks unlike notch | OSD is a separate layer but **morphs from island width** when `Settings.bar === island`; lock/greeter use **LockOsd** (bottom pill) | Session: island bar + `brightness.sh watch --part osd`; greeter: brightness only without PipeWire user |
| F7/F8 do nothing | Binds only existed when `~/Scripts/brightness.sh` present | Now fall back to `brightnessctl` always |
| No WhatsApp toasts | DND, shell down, ZapZap backend disabled | `rice doctor`; restart ZapZap after shell outage |
| Double notifications | Hot reload + keepOnReload | By design; dismiss duplicates |
| Limit alert on every reload | Restart | What was said is kept in `~/.local/state/rice/limits-told.json` (once per window per reset) |
| Memory >450 MB after reload | Quickshell hot reload | `rice-check`; restart shell if over budget |
| `notify-send` broken | libnotify | All kuwai/shell paths use `rice-notify` |

Run **`bin/rice doctor`** after promote or when notifications feel dead.
