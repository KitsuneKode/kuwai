# Handoff: 2026-11-17 → 18 session (links, reliability, lifecycle, tooltip, UI polish)

What one session changed in kuwai (`~/Projects/rice`), and outside it, so other agents
working here know what moved, what is in flight, and what to leave alone.
State as of 2026-11-18 21:10 IST.

## Where things are

| What | Branch / place | Live? |
|---|---|---|
| Stable (what the desktop runs) | `stable` at `2c82a55`, checkout `~/.local/share/kuwai` | yes |
| Working branch | `feat/assistant-agent` at `42a726e` (+ this doc) | no, needs `bin/kuwai promote` |
| UI polish | `fix/ui-polish-20261118` at `0ba5c62`, worktree `.worktrees/ui-polish-20261118` | no. **Unmerged; merges cleanly into `feat/assistant-agent`.** Don't delete the worktree or branch. |
| smart-browser (link opener) | `~/.local/bin/smart-browser` (not in any repo) | yes |

## What changed, by commit

### Helpers and island (`feb1015`, `2c82a55`, now on stable)
- `feb1015` makes the backup, recording and capture helpers reliable: `kuwai-backup`, `kuwai-rec`, `kuwai-shot`, `kuwai-term`, `kuwai-wall`, `lib/dispatch.sh` and the clipboard's capture path, with a test for each.
- `2c82a55` keeps dense island activities readable and reachable:
  - IslandSplit and IslandActivities fit up to five activities directly or behind an overflow.
  - Tooltips wrap long text.
  - It also touches drag release and cancellation, the pointer's proximity zone, and RaisedButton padding.
  - The audit write-up is `docs/research/2026-11-18-reliability-audit.md`.
  - The island tests are `tests/ui/island.qml` and `tests/shell/island-reliability.test.mjs`.

### Tooltip (`4f2ec52`, on `feat/assistant-agent`)
- An output can report a width of 0 for a moment, and `Tip.qml` used to collapse into a one-letter column when it did. The text width now comes from the first screen wide enough to hold readable text, else the panel width.
- The label is sized from a hidden copy of the text that is never cut short.
- The height rounds up.
- `tests/ui/island.qml` stage 0 covers this.

### Resource lifecycle (`42a726e`, on `feat/assistant-agent`)
- The live wallpaper's players are released under the lock, the screensaver and powered-off displays.
- Clipboard caches are pruned against history, and an async reply that arrives late is dropped.
- ClipCard ignores a render reply meant for the entry it showed before.
- The screensaver reconciles its film process, falls back to Dusk after a crash, and drops the drawn scene while locked or off.
- Notifications replayed after a reload are released when nothing in history matches them.
- WallFx cancels a transition when a new wallpaper replaces it.
- MemLog records saver, displays-off and wallpaper state.
- The write-up is `docs/research/2026-11-18-resource-lifecycle-audit.md`, and the tests are in `tests/shell/resource-lifecycle.test.mjs`.

### UI polish (`0ba5c62`, on `fix/ui-polish-20261118`)
- **Waveforms.** IslandHover's 13 bars and MediaPanel's 6 were redrawn on every frame while music played: each audio peak restarted a 90 ms Behavior, and every bar had its own timer. They now follow IslandRest's pattern:
  - one 20 Hz tick sets the bars directly;
  - the jitter changes on every 3rd tick;
  - the bars only ease (`Theme.waveSettleMs`) when they settle into the pause shape.
- **New Theme tokens.** Use them instead of typing whites:
  - `rowHover`, 0.06, for a list or menu row;
  - `ghostHover`, 0.1, for a glyph button on glass;
  - `tileRest` and `tileHover`, 0.065 and 0.1, for a tile that always shows its surface.

  19 call sites moved to them. 11 pill-style buttons that changed colour instantly now fade over `Theme.hoverMs`. Menu rows stay instant on purpose.
- **Small text.**
  - Badges, counts and keycaps use `Theme.tCaption` (10 px).
  - Readable sentences use `Theme.tFootnote` (11 px): UpdatesPanel's notes, AlertBanner's "Tap for more", and NotifPeek's hint, which now elides.
  - UpdatesPanel's repo tag uses `textTertiary`.
- **`Theme.screenSize(screen, axis, fallback)`.** It ignores a reported size under 320 px (`Theme.minScreen`). Popups, Center, IslandBar, AssistantOverlay, ClipboardPanel, SystemPanel and UsagePanel size their windows through it. **New code must not size a window from `screen.width` or `modelData.height` directly.**
- **Ellipsis.** The assistant's search placeholder uses `…`.
- **Tests.** `tests/shell/ui-polish.test.mjs` encodes all four rules (screen size, waveforms, hover fills, ellipsis), and those checks fail on the old code.
- **Verified:**
  - bun: 313 pass
  - pytest: 433
  - Lua tests
  - `kuwai-tokens --check`
  - `kuwai-ui-test`: the island case at 1×, 1.2× and 2× text, and the X11 compile of all 143 components and modules
- **Not verified:** the hover view and the waveforms on the real desktop, because that needs a real pointer and music playing.

### Outside the repo
- **T3 Code links.** No T3 source was changed. The saved setting is now `browserLinkTarget: "app"`, so:
  - an ordinary click opens in the integrated browser;
  - Ctrl or Cmd-click opens the system browser;
  - right-click offers both.

  The reverse mapping (plain click to external) does not exist in T3. Adding it would mean one shared resolver used by chat, the terminal, documents, PRs and diffs. The analysis is in the session scratch, `link-routing-investigation.md`.
- **`~/.local/bin/smart-browser`** was rewritten in standard-library Python:
  - one `hyprctl` snapshot with a 0.5 s timeout;
  - exact matching on browser window classes, with app and PWA windows filtered out;
  - focus ranks are validated, and it falls back to the next browser if one fails;
  - targets are validated before anything opens.

  It passes 27 tests. To roll back, run `install -m 755 ~/.t3/scratch/2026-11-17-find-out-why-like-we-802b1b1a/smart-browser.original ~/.local/bin/smart-browser`.

## Rules to keep (each came from a bug this session)
1. Size windows through `Theme.screenSize`. Size tooltip and label text from what the text actually needs, never from an elided or wrapped width (that feeds back into itself).
2. A value fed by audio peaks or positions is never behind a Behavior while live. Sample it on one shared Timer and set it directly.
3. Hover fills come from the Theme tokens above, never `Qt.rgba(1, 1, 1, 0.0x)`.
4. Work in `.worktrees/<name>`. Commit only your own files, because the main checkout often holds another agent's uncommitted work. Only `bin/kuwai promote` moves stable.
5. Before you call something done, run the five checks in AGENTS.md, plus `bin/kuwai-ui-test --case island --text-scale 2` and `--case primitives --compile-components --backend x11` for QML changes.
6. **Unresolved conflict:** `.claude/skills/kuwai-ui` says "never below 11 px", but Theme defines `tCaption` as 10 px for badges. Decide which wins and fix the other.

## Memory and processes (measured 2026-11-18 ~20:50)
- **The shell (`qs`) is the biggest problem:** about 1.2 GB of RAM plus 0.7 GB swapped out, against the 450 MB budget. The cause is the two live-wallpaper players inside the shell. `42a726e` releases them when they're hidden, not while they're visible. The real fix is to move playback out of the shell, for example into mpv.
- **Swap:** 13.5 GB used, 9.2 GB of it on disk. Other large processes:
  - voxtype, about 1.3 GB including swap (its whisper model);
  - Hyprland, about 0.8 GB.
- **Python is small:** about 250 MB in all. In order of size:
  - SearXNG in Docker, about 113 MB, mostly swapped;
  - auto-cpufreq, about 40 MB;
  - kuwai-feeds, about 38 MB;
  - `brightness.py --serve`, about 25 MB;
  - voxtype-llm-proxy, about 17 MB.
- **Brightness daemon version skew.** `brightness.py --serve` was started from `~/Projects/rice`, not the stable copy. It detaches and has run since boot with no parent. Stable's `kuwai-brightness` connects to that same socket, so brightness runs working-copy code. The fix: the client should restart the daemon when a different copy (path or version) started it. Until then, `pkill -f 'brightness.py --serve'` resets it.

## Priorities, in order
1. Merge `fix/ui-polish-20261118` into `feat/assistant-agent`, run the checks, then `bin/kuwai promote` and `kuwai-check`. Until then none of the work above is live.
2. Move live-wallpaper playback out of the shell, which is the RAM problem above.
3. Fix the brightness daemon version skew.
4. Live checks no fixture can do:
   - both monitors, mixed-scale and rotated outputs;
   - suspend, resume and monitor unplug;
   - idle CPU, and a trace of the drawn screensaver's ~32 % CPU on the 165 and 200 Hz screens;
   - a screen reader;
   - an overnight soak with `kuwai-check --soak`.
5. Version `smart-browser` in the repo (`bin/` or `lib/`, the way `lib/brightness` is), so it isn't an untracked file in `~/.local/bin`.
6. Settle the 10 px vs 11 px rule.
7. Prune worktrees: there are 20, and many sit at old detached commits. Merge or delete each one on purpose; `fix/ui-polish-20261118` is not a leftover.
8. Open requests (`docs/REQUESTS.md`):
   - clipboard multi-select;
   - night light in the notification panel;
   - the notification center growing out of the island;
   - the kittymux redesign.
