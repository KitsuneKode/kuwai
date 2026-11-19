# Working on kuwai (for coding agents)

kuwai is a Hyprland desktop: `hypr/` (the session, Lua, Hyprland 0.57) and
`shell/` (the island, panels, notifications, lock, login face; Quickshell/QML).
`bin/` and `lib/` are its helpers, `greeter/` and `system/` the two parts that
need root, `tests/` the suites. `refs/` holds other projects' clones for
reading only: never edit, never copy code from a GPL one.

## Read first

- `docs/DESIGN.md` and `shell/config/Theme.qml`: the design system. Never type a
  size, duration or colour Theme already names (`bin/kuwai-tokens --check`).
- `.claude/skills/kuwai-ui/SKILL.md`: how every surface is built (motion,
  gestures, type, states, cost).
- `.claude/skills/verify-kuwai/SKILL.md`: how to prove a change on the live
  session without touching the owner's pointer, keyboard, focus or media.
- `docs/design/REHEARSAL.md`: how a panel is looked at before the session sees
  it. A new panel or a new state gets a scene in `tests/ui/scenes.json`.
- `docs/PLAN-kuwai.md`, `docs/PLAN-launch.md`: what is in flight and in what order.

## The live session is the owner's

The running shell is usually this checkout with file watching on: saving a
file under `shell/` reloads their desktop. Work in `.worktrees/<name>/`, check
there, then bring the change over in one go.

- Never type synthetic text, move the pointer, open a keyboard-grabbing panel,
  or play/pause media to test. Use `qs ipc -p shell call test …` and `grim`.
- A failed reload keeps the old shell running and says so only in the log
  (`qs log -p shell | grep -nE "Failed to load|Configuration Loaded" | tail -2`).

## Checks (all must pass before a change is done)

```sh
python -m pytest -q -p no:cacheprovider tests      # helpers, updater, installer, greeter, security lints
bun test                                           # shell logic (bunfig.toml scopes it to this repo)
for t in tests/hypr/test_*.lua; do lua "$t"; done  # Hyprland config logic
bin/kuwai-tokens --check                            # literals never go up
bin/kuwai-check                                     # the running shell: load, orphans, idle, memory, CPU, compile
bin/kuwai-rehearse --gate                           # every panel in every state, pictured and judged (a minute; then open the sheet)
```

## Rules that came from real failures

- Text from outside the shell goes in a `Label`, or a `Text` with
  `textFormat: Text.PlainText`. Markup is built only from escaped strings.
- A value reaches a command as an argument (`["sh", "-c", script, "sh", value]`),
  never pasted into the script.
- Links are opened only after `Links.safeLink` (`shell/services/links.mjs`: the
  web and mail; `Turn.safeLink` is the same function). `tests/security/test_links.py`.
- A surface that isn't showing isn't mapped (1×1 or a `LazyLoader`); a helper
  that isn't needed isn't running; a streaming helper starts under
  `setpriv --pdeathsig`.
- Nothing under `greeter/` or `system/` runs as root what a user-writable file
  can change.
- A length that holds text is `Theme.sp(n)` (it grows with Text size); a
  message never names a helper, an exit status or a path.
- Commit only when asked; the stable channel moves only with `bin/kuwai promote`.
